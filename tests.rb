# testing for project rubin
require_relative 'classes.rb'
db = DatabaseBox.new
db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)

# adapter = EncryptedAdapter.new
# adapter.write_encrypted_message(Time.now, 'email', false, 'Johnathan', 'important', nil)

# cb = CryptoBox.new
# cb.testing_generate_receiving_keypair

puts db.output_all_keys
# puts db.output_host_keypair  # => public private