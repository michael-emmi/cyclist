#!/usr/bin/env ruby

require 'optparse'
require 'ostruct'
require 'Set'

$verbose = false

module SimpleInterpreter
  # The simplest possible log interpreter.
  # Interprets the following lines as expected.
  #
  # start 1
  # access 1 10
  #
  # start 2
  # access 2 10
  # access 2 20
  #
  # start 3
  # access 3 20
  #
  # complete 2
  #
  # access 1 10
  #
  # complete 1
  # complete 3

  def self.readline(line)
    line = (line.split('#').first || "").strip
    return nil if line.empty?

    line.match(/\Astart (?'id'\d+)\Z/) do |m|
      return :start, m[:id].to_i
    end
    line.match(/\Acomplete (?'id'\d+)\Z/) do |m|
      return :complete, m[:id].to_i
    end
    line.match(/\Aaccess (?'id'\d+) (?'obj'\d+)\Z/) do |m|
      return :access, m[:id].to_i, m[:obj].to_i
    end
    puts "INVALID LINE: #{line}"
    return nil
  end
end

class ConflictTracker
  def initialize(interpreter)
    @interpreter = interpreter
    @objs = {}
    @accs = {}
    @future = {}
    @preds = {}
    @succs = {}
  end

  def live?(agent)
    !@accs[agent].nil?
  end

  def accesses(agent)
    @accs[agent] + @future[agent]
  end

  def cycle?(agent)
    @preds[agent].include?(agent)
  end

  def to_s
    @accs.map do |a,os|
      "agent #{a}: accesses {#{os.map(&:to_s) * ", "}} " +
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

    puts "FOUND CYCLE IN AGENT #{agent}" if cycle?(agent)

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

  def read(file)
    File.open(file) do |f|
      f.each do |line|
        step, *args = @interpreter.readline(line)
        next if step.nil?
        if $verbose
          puts ("-" * 80)
          puts "ACTION: #{step} #{args * " "}"
        end
        send(step, *args)
        if $verbose
          puts ("-" * 80)
          puts "STATE\n#{self}"
          puts ("-" * 80)
        end
      end
    end
  end

end

begin
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

  ConflictTracker.new(SimpleInterpreter).read(execution_log)
end
