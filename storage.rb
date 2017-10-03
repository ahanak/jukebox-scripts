require 'yaml'

# Store associations of tag uids to songs in a simple yaml file.
# This class will handle the serialization and deserialization
# and automatically persist the data if any change happens.
class TagsStorage
  # Loads the given yaml file
	def initialize(file)
		@file = file
		@data = load
	end

  # Access the data stored with the given id.
  # @params [String] tag_id is the uid of the nfc tag.
  def [](tag_id)
		@data[tag_id]
	end

  # Store data which should be associated with the given id.
  # @params [String] tag_id is the uid of the nfc tag.
  # @params [Object] song_url is any data (one or multiple songs).
	def []=(tag_id, song_url)
		@data[tag_id] = song_url
		store
	end

	private

  # Deserialize the stored YAML file.
	def load
		res = {}
		if File.exists? @file
			res = YAML.load_file(@file)
		end
		return res
	end

  # Serialize to YAML and store in a file.
	def store
		File.open(@file, 'w') {|f| f.puts @data.to_yaml}
	end
end
