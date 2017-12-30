#!/usr/bin/env ruby

require 'ruby-mpd'
require 'thread'
require 'uri'


$:.unshift File.dirname(__FILE__)
require 'button_observer'
require 'nfc-detector'
require 'mqtt'
require 'storage'
require 'user_feedback'

# Create a child process for the nfc stuff
$nfc_pid = fork do
	# Child process for the slow nfc things that would otherwise block the whole process with all its threads
	# Use MQTT for inter process communication (publish here)
	MQTT::Client.connect('localhost') do |mqtt|
	  nfc = NfcDetector.new ->(uid) {puts "Detected #{uid}"; mqtt.publish('jukebox/nfc', uid)}
	  nfc.join
	end
end

def shutdown
	begin
		Process.kill 'TERM', $nfc_pid
		Process.wait
	ensure
		exit 0
	end
end

Signal.trap("INT") { shutdown }
Signal.trap("TERM") { shutdown }

# The file to load the nfc tag ids and associated tracks from
DATABASE= ARGV.first || 'tags.yml'

# Our even queue. Multiple Threads will put events in there (e.g. if a button is pressed or a nfc tag is detected).
# The main loop will then process these events in the main logic
EVENTS = Queue.new

# The Events are simple structs
class NfcEvent < Struct.new(:id); end
class ButtonEvent < Struct.new(:button, :pressed); end


# Try to select the other songs that should be queued with the selected one.
# @return an array of url or an empty array on any error
def generate_queue_for_song(mpd, url_string)
  uri = URI.parse(url_string)
	case uri.scheme
    when 'file'
      generate_queue_for_file_song(mpd, uri)
    when 'local'
      generate_queue_for_db_song(mpd, uri)
    else
      []
	end
end

def generate_queue_for_file_song(mpd, uri)
  path = URI.decode uri.path
  directory = File.dirname(path)
  extension = File.extname(path)

  dir_songs = []

  # Glob for e.g. /path/to/dir/**/*.mp3 to get all files with the same extension in this directory
  begin
    dir_songs = Dir.glob(File.join(directory, '**/*' + extension))
  end
  dir_songs.sort!
  return dir_songs.collect! {|path| 'file://' + URI.encode(path)}
end

def generate_queue_for_db_song(mpd, uri)
  # Query the url in the database to retrieve the album name
	s = mpd.where(file: uri.to_s).first
	album_songs = []
	unless s.nil?
		puts s.inspect
		album_songs = mpd.where({:album => s.album}, {:strict => true})
		album_songs.sort!{|s1,s2| s1.track <=> s2.track}
		#puts album_songs.inspect
	end
	return album_songs.collect!{|s| s.file}
end

# Our Main program loop containing the most important logic
def main
	# create a client for MPD, the music player daemon
	mpd = MPD.new
	mpd.connect

	# We do not run the NfcDetector in the main process because it wil make the whole script extremely slowly reacting.
	#nfc = NfcDetector.new(->(id) {puts "NFC #{id}!"; EVENTS << NfcEvent.new(id)})

	# Instead, we use MQTT as inter process communication
	# Subscribe to a topic in an extra thread and put everything in the event queue
	mqtt_tread = Thread.new do
		MQTT::Client.connect('localhost') do |mqtt|
			mqtt.get('jukebox/nfc') {|t, p| EVENTS << NfcEvent.new(p)}
		end
	end

	# We want to listen to some buttons which are connected to the GPIO pins.
	# The button config is just a list of these buttons in the form name => BCM pin number
	button_cfg = {
		:prev => 21,
		:next => 20,
		:record => 26
	}
	# Create an observer which will execute the given lambda if a pin changes.
	# The lambda creates an event and puts it into the event queue.
	buttons = ButtonObserver.new(button_cfg, ->(name, status) {puts "Button #{name}: #{status}!"; EVENTS << ButtonEvent.new(name, status)})

	# Initialize our database which will store the association of tag uid and song paths.
	data = TagsStorage.new(DATABASE)

	# This is a state variable which will be true as long as the record button is pressed.
	recording = false

	loop do
		# Get the next event from the queue or block until one is available
		event = EVENTS.pop

		# Process each event differently
		case event
		when NfcEvent
			# a nfc tag is detected
			# -> play song as default
			# -> store the currently playing song together with this tag id if record button is pressed

			# the tag id
			id = event.id

			if data[id] == 'command:pause'
				# first case in if / elsif construct to make this tag not overwriteable
				mpd.pause = !mpd.paused?
			elsif recording
				# Find out what song is currently played and store its path together with the tag id
				song = mpd.current_song
				if song
					song = song.file
					puts "NEW TAG RECORDED: #{id} -> #{song}"
					UserFeedback.ok
					data[id] = song
				end
			else
				# default behavior: Play the song associated with this tag
				puts "Will Play: #{id} -> #{data[id]}"
				next unless data[id]
				UserFeedback.ok
				mpd.clear if mpd.queue.count > 0

#				mpd.add data[id]
				times_next = 0
        album_songs = generate_queue_for_song(mpd, data[id])
				puts "Found #{album_songs.size} songs."
				if album_songs.size > 0
					puts "Album found - trying to add"
					found = false
					stored_song = URI.decode(data[id]) 
					album_songs.each do |s|
						mpd.add s
						current_song = URI.decode(s)
						found = true if current_song == stored_song
						puts "#{current_song} == #{stored_song}"
						times_next += 1 unless found
					end
					puts (found ? "Found": "Not Found")
					times_next = 0 unless found
				else
					mpd.add data[id]
				end
				mpd.play

				puts "Skipping #{times_next} songs."
				sleep 0.5 if times_next > 0
				times_next.times { mpd.next }
				#mpd.play

			end # recording
		when ButtonEvent
			# a button was pressed, react in the right way
			case event.button
			when :prev
				if event.pressed
					puts "Prev"
					mpd.previous
				end
			when :next
				if event.pressed
					puts "Next"
					mpd.next
				end
			when :record
				UserFeedback.record_mode(event.pressed)
				recording = event.pressed
			end
		end
	end

	# wait for the mqtt thread to finish (only reached e.g. on SIGTERM)
	mqtt_tread.join
end

UserFeedback.boot_complete

# Catch exceptions in the main an restart the main again if any exception ocured
begin
	main
rescue => e
	puts e
	puts e.backtrace
	retry
end
