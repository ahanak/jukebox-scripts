#!/usr/bin/env ruby

$:.unshift File.dirname(__FILE__)
require 'button_observer'
require 'nfc-detector'
require 'mqtt'

MQTT::Client.connect('localhost') do |mqtt|
  nfc = NfcDetector.new ->(uid) {puts "Detected #{uid}"; mqtt.publish('jukebox/nfc', uid)}
  nfc.join
end
