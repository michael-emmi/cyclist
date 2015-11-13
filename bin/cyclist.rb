#!/usr/bin/env ruby

require 'optparse'
require 'Set'

# Just for illustration purposes.
module SimpleInterpreter
  E = {
    start: /\Astart (\d+)\Z/,
    complete: /\Acomplete (\d+)\Z/,
    access: /\Aaccess (\d+) (\d+)\Z/,
  }

  def self.readline(line)
    E.each do |act,expr|
      line.match(expr) do |m|
        return act, *m.to_a.drop(1).map(&:to_i)
      end
    end
    puts "INVALID LINE: #{line}"
    return nil
  end
end

module EventActionInterpreter
  E = {
    # Start and complete actions are implicit.
    access: /\AEvent:\s+(\d+|null)\s+[A-Z]{3}\s+(\d+)\s+.*\Z/,
  }
  
  def self.readline(line)
    E.each do |act,expr|
      line.match(expr) do |m|
        return act, *m.to_a.drop(1).map(&:to_i)
      end
    end
    puts "INVALID LINE: #{line}"
    return nil
  end
end

class ConflictTracker
  def initialize
    @objs = {}
    @accs = {}
    @future = {}
    @preds = {}
    @succs = {}
  end

  def agents;           @accs.keys end
  def live?(agent)      !@accs[agent].nil? end
  def accesses(agent)   @accs[agent] + @future[agent] end
  def cycle?(agent)     @preds[agent].include?(agent) end

  def to_s
    return "no live agents" unless agents.count > 0
    agents.map do |a|
      "agent #{a}: accesses {#{@accs[a].map(&:to_s) * ", "}} " +
      "future {#{@future[a].map(&:to_s) * ", "}} " +
      "before {#{@succs[a].map(&:to_s) * ", "}}"
    end * "\n"
  end

  def start(agent)
    @accs[agent] = Set.new
    @future[agent] = Set.new
    @preds[agent] = Set.new
    @succs[agent] = Set.new
  end

  def complete(agent)
    return unless live?(agent)

    accesses(agent).each do |o|
      @objs[o].merge(@preds[agent])
      @objs[o].delete(agent)
    end
    @preds[agent].each do |a|
      @succs[a].merge(@succs[agent])
      @succs[a].delete(agent)
      @future[a].merge(accesses(agent))
    end
    @succs[agent].each do |a|
      @preds[a].merge(@preds[agent])
      @preds[a].delete(agent)
    end
    @accs.delete(agent)
    @future.delete(agent)
    @preds.delete(agent)
    @succs.delete(agent)
  end

  def access(agent, object)
    start(agent) unless live?(agent)
    @objs[object] ||= Set.new
    @objs[object].each do |a|
      next if agent == a && !@future[a].include?(object)
      @preds[agent] << a
      @succs[a] << agent
    end
    @objs[object] << agent
    @accs[agent] << object
  end
end

def step(tracker, action, agent, *args)
  if $verbose
    puts ("-" * 80)
    puts "ACTION: #{action} #{agent} #{args * " "}"
  end

  tracker.send(action, agent, *args)

  if $verbose
    puts ("-" * 80)
    puts "TRACKER\n#{tracker}"
    puts ("-" * 80)
  end
end

begin
  $verbose = false

  OptionParser.new do |opts|
    opts.banner = "Usage: #{File.basename $0} [options] FILE"
    opts.separator ""

    opts.on("-h", "--help", "Show this message.") do
      puts opts
      exit
    end

    opts.on("-v", "--verbose", "Display informative messages too.") do |v|
      $verbose = v
    end
  end.parse!
  
  execution_log = ARGV.first
  unless execution_log && File.exists?(execution_log)
    puts "INVALID/MISSING EXECUTION LOG FILE #{execution_log}"
    exit
  end

  tracker = ConflictTracker.new
  interpreter = EventActionInterpreter
  agents = Set.new
  objects = Set.new
  steps = 0
  cycle = false
  start_time = Time.now

  File.open(execution_log) do |f|
    f.each do |line|
      line = (line.split('#').first || "").strip
      next if line.empty?
      action, agent, *args = interpreter.readline(line)
      next if action.nil?
      cycle ||= tracker.live?(agent) && tracker.cycle?(agent)
      step(tracker, action, agent, *args)
      agents << agent
      objects << args.first if args.count > 0
      steps += 1
    end
  end

  tracker.agents.each do |agent|
    cycle ||= tracker.live?(agent) && tracker.cycle?(agent)
    step(tracker, :complete, agent)
    steps += 1
  end

  puts "agents: #{agents.count}"
  puts "objets: #{objects.count}"
  puts "steps:  #{steps}"
  puts "cycle:  #{cycle}"
  puts "time:   #{(Time.now - start_time).round(3)}s"

end
