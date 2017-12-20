# This class signals internal states like success or errors to the user.
# The current implementation uses sounds, but also other feedback channels like LEDs could be possible.
class UserFeedback
  def self.boot_complete
    Sound.beep
  end

  def self.ok
    Sound.beep
  end

  def self.record_mode(turnedOn)
    Sound.beep if turnedOn
  end

  # Subclass for playing sounds
  class Sound
    def self.beep
      play 'beep.wav'
    end
    private
    SOUNDS_FOLDER = File.join(File.dirname(__FILE__), 'sounds')
    def self.play(filename)
      path = File.join(SOUNDS_FOLDER, filename)
      fork { exec("aplay '#{path}'") }
    end
  end
end
