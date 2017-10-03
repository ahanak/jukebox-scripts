require 'pi_piper'
require 'thread'

# Observes any number of IO Pins. Uses a library which is written for that purpose.
# I think/hope PiPiper uses interrupts for that.
class ButtonObserver
  # As a default, button pins are inputs and we use the internal pull up resistors.
  # Using pull up resistors means, that we need to revert the logic level as LOW corresponds to a pressed button.
  # Using this config allows us to connect each button directly with one GPIO and GND.
	DEFAULT_OPTS = {:direction => :in, :pull => :up, :invert => true}

  # Start the observer with the given callback.
  # @param [Hash] button_pins is a hash with keys as names and values as BCM pin number
  # @param [lambda(name, pressed)] callback is given as lambda with two arguments:
  #   the name of the changed button and if it is pressed or not.
	def initialize(button_pins, callback)
		@button_pins = button_pins
		@callback = callback
		@thread = Thread.new do
			begin
				run
			rescue => e
				puts "Thread died: #{e}"
				puts e.backtrace
			end
		end
	end

  private

  # do the work
	def run
		@button_pins.each do |name, pin_cfg|
			pin_options = DEFAULT_OPTS
			if pin_cfg.is_a? Hash
				pin_options = pin_options.merge(pin_cfg)
			else
				pin_options = pin_options.merge(pin: pin_cfg)
			end

			PiPiper.watch pin_options do |pin|
				begin
					pin.read # set last_value and value correct
					@callback.call(name, pin.on?)
				rescue => e
					puts "Error in Button Procesing: #{e}"
					puts e.backtrace
				end
			end
		end
		PiPiper.wait
	end
end
