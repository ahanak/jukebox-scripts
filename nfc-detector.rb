require 'ruby-nfc'
require 'thread'

# This class scans for NFC Tags and if one is detected, the callback is executed with the uid of that tag.
class NfcDetector
  # @param [labmda(uid)] callback_lambda is the lambda with one argument, the tag uid.
	def initialize(callback_lambda)
		@callback = callback_lambda
		@thread = Thread.new do
			begin
				run
			rescue => e
				puts "Thread died: #{e}"
				puts e.backtrace
			end
		end
	end

  # Wait for the thread to finish.
  def join
    @thread.join
  end

  private

  # do the work
	def run
		readers = NFC::Reader.all
		puts "Available readers: #{readers}"

		# The order of tag types in poll arguments defines priority of tag types
		callback_local = @callback # this is required because damn nfc lib uses instance_eval for the block...
		readers.first.poll(NFC::Tag) do |tag| # IsoDep::Tag, Mifare::Classic::Tag
			begin

				callback_local.call(tag.uid_hex.upcase)
			rescue => e
				puts "Error in TAG processing: #{e}"
				puts e.backtrace
			end
		end
	end
end

# Variant using the NFC lib
=begin
require 'nfc'
class NfcDetector
	def initialize(callback_lambda)
		@callback = callback_lambda
		@thread = Thread.new do
			begin
				run
			rescue => e
				puts "Thread died: #{e}"
				puts e.backtrace
			end
		end
	end

	def run
		# Create a new context
		ctx = NFC::Context.new

		#Open the first available USB device
		dev = ctx.open nil

		last_id = nil
		loop do
			begin
				id = dev.select.to_s
				if id != last_id
					last_id = id
					@callback.call(id)
					sleep 1
				end
		  rescue => e
			  puts "error in processing: #{e}"
			  puts e.backtrace
			end
		end
	end
end
=end
