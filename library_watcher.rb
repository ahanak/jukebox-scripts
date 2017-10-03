#!/usr/bin/env ruby
require 'rb-inotify'
require 'thread'

DIRECTORIES = [ "/srv/music" ]
WAIT_FOR_FURTHER_CHANGES_SECONDS = 5

notifier = INotify::Notifier.new
queue = Queue.new
DIRECTORIES.each do |libdir|
  notifier.watch(libdir, :move, :create, :delete, :recursive) do
    queue << libdir
  end
end

Thread.new do
  loop do
    queue.pop
    queue.clear
    sleep WAIT_FOR_FURTHER_CHANGES_SECONDS

    # Only perform scan if no new events happened while sleeping
    if queue.size == 0
      `mopidyctl local scan`
    end
  end
end

notifier.run
