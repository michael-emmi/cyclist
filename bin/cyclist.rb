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
  def self.readline(line)
    line.match(%r{
      \A
      Event:\s+(?'event'\S+)
      \s+
      (?'action'\S+)\s+(?'object'\S+)\s+(?'type'\S+)\s+(?'field'\S+)
      \s+
      Thread:\s+(?'thread'.*)
      \Z
    }x) do |m|
      return :access, m[:event], "#{m[:object]}.#{m[:field]}", m[:action]
    end
    puts "INVALID LINE: #{line}"
    return nil
  end
  def self.conflict?(action1, action2)
    action1 == 'PUT' || action2 == 'PUT'
  end
end

class ConflictTracker
  def initialize(conflict_fn)
    @conflict_fn = conflict_fn
    @objs = {}
    @accs = {}
    @future = {}
    @preds = {}
    @succs = {}
  end

  def agents;           @accs.keys end
  def live?(agent)      !@accs[agent].nil? end
  def cycle?(agent)     @preds[agent].include?(agent) end

  def accesses(agent)
    @accs[agent].merge(@future[agent]){|_,ms1,ms2| ms1.merge(ms2)}
  end

  def to_s
    return "no live agents" unless agents.count > 0
    agents.map do |a|
      "agent #{a}: accesses {#{@accs[a].map{|o,ms| "#{o}(#{ms.map(&:to_s) * ","})"} * ", "}} " +
      "future {#{@future[a].map{|o,k| "#{o}(#{ms.map(&:to_s) * ","})"} * ", "}} " +
      "before {#{@succs[a].map(&:to_s) * ", "}}"
    end * "\n"
  end

  def start(agent)
    @accs[agent] = {}
    @future[agent] = {}
    @preds[agent] = Set.new
    @succs[agent] = Set.new
  end

  def complete(agent)
    return unless live?(agent)
    accesses(agent).each do |o,ms|
      @objs[o].merge(@preds[agent])
      @objs[o].delete(agent)
    end
    @preds[agent].each do |a|
      @succs[a].merge(@succs[agent])
      @succs[a].delete(agent)
      @future[a].merge(accesses(agent)){|_,ms1,ms2| ms1.merge(ms2)}
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

  def access(agent, object, method)
    start(agent) unless live?(agent)
    @objs[object] ||= Set.new
    @objs[object].each do |a|
      if @future[a][object] && @future[a][object].any?{|m| @conflict_fn.call(m,method)} ||
        agent != a && @accs[a][object] && @accs[a][object].any?{|m| @conflict_fn.call(m,method)}
      then
        @preds[agent] << a
        @succs[a] << agent        
      end
    end
    @objs[object] << agent
    @accs[agent][object] ||= Set.new
    @accs[agent][object] << method
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
  
  puts "Serious Cyclist version 0.3"

  execution_log = ARGV.first
  unless execution_log && File.exists?(execution_log)
    puts "INVALID/MISSING EXECUTION LOG FILE #{execution_log}"
    exit
  end

  tracker = ConflictTracker.new(EventActionInterpreter.method(:conflict?))
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

  puts "-" * 60
  puts "trace:  #{execution_log}"
  puts "agents: #{agents.count}"
  puts "objets: #{objects.count}"
  puts "steps:  #{steps}"
  puts "cycle:  #{cycle}"
  puts "time:   #{(Time.now - start_time).round(3)}s"
  puts "-" * 60

end
