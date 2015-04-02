# testing for project rubin
require_relative 'classes.rb'
db = DatabaseBox.new
# db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)

adapter = EncryptedAdapter.new
adapter.write_encrypted_message(Time.now, 'email', false, 'Johnathan', 'long_text', 'NULL')

cb = CryptoBox.new
puts 'blah'
cb.testing_generate_receiving_keypair

# puts db.output_all_keys
# puts db.output_host_keypair  # => public private

# irc = RelayChat.new('happybot', 'none', 'irc.freenode.org', '#asdfjhasdkjfh')
# adapter.read_encrypted_message_by_id(1, 2)

puts db.output_new_message_ids(2, 10)