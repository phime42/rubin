require 'rubygems'
require 'bundler/setup'
require 'cinch'
require 'time'
require 'sequel'
require 'nacl'
require 'securerandom'
require 'sqlite3'
require 'digest'
require 'base64'

$dbpath = "sqlite://test.db"

class Logger
  include Cinch::Plugin

  listen_to :private,    :method => :register_private_message
  listen_to :disconnect, :method => :disco
  listen_to :channel,    :method => :register_public_message

  def initialize(*args)
    super
    @short_format = "%Y-%m-%d"
    @long_format = "%Y-%m-%d %H:%M:%S"
  end
 
  def disco(*)
    puts 'got disconnected'
  end
 
  # registers a public message on the channel
  def register_public_message(message)
    db = DatabaseBox.new
    db.write_message_to_database(Time.new, 'client', false, message.user.name, message.message, nil)
  end

  def register_private_message(message)
    db = DatabaseBox.new
    db.write_message_to_database(Time.new, 'private', true, message.user.name, message.message, nil)
    #puts "#{Time.new} #{message.user.name} whispers: #{message.message}"
  end

end

class RelayChat
  def initialize(nick, realname, server, channels)
    bot = Cinch::Bot.new do
    configure do |c|
      c.nick = nick
      c.realname = realname
      c.server = server
      c.channels = [channels]
      c.plugins.plugins = [Logger]
    end
    end
    bot.start

    def send_message(nick, recipient)
    # sends a private message to the desired nick
    puts 'virtual message'

  end
  end
end

class DatabaseBox  # todo: rewrite DatabaseBox to be a more generic accessor for databases
  attr_reader :messages_ds  # make dataset readable
  def initialize
    # check if database was used before, otherwise generate what we need
    @DB
    @messages_ds
    @keys_ds

    if !File.exist?(File.basename($dbpath))
      setup_message_database
      setup_key_database
    end

    @DB = Sequel.connect($dbpath)
    @messages_ds = @DB[:messages]  # create dataset for messages
    @keys_ds = @DB[:keys]  # create dataset for keys

  end

  def write_message_to_database(timestamp, client, private, sender, message, attachment)
    # write the message from the client application to the database
    @messages_ds.insert(:time => timestamp, :client => client, :private => private, :sender => sender, :message => message, :attachment => attachment)
  end

  def read_messages_from_database()
    # read a message from database
    # puts @messages_ds.all
    # puts @messages_ds.get(:time)
    # puts @messages_ds.each{|x| p x.name}
  end

  def register_key (description, host, private_key, public_key)  # todo: check whether it's a real key or not
    # write key to key database and register it as a new column in the messages database
    @keys_ds.insert(:description => description, :host => host, :private_key => private_key, :public_key => public_key, :revoked => false)
    if !private_key.empty?  # todo: check whether the key is already a column in the message table
      add_new_messages_column(public_key)
    end
  end

  def revoke_key(public_key)
    # checks whether the respective to be revoked key is already a column in the messages and deletes it
    if check_for_column(:messages, public_key)
      delete_messages_column(public_key)
    end
  end

  def output_host_keypair
    # outputs the server's public !!!and private!!! keypair,
    # so proceed with caution.
    #   # checks whether there's a private key saved
    #   if check_for_revocation(key_id)
    #     @keys_ds.select_group(:private_key)
    #   end
    # end
    # @keys_ds.select_group(:private_key).to_a.each do |x|
    #   puts x[:private_key]
    # end
    # if @keys_ds.where(:private_key).empty?
      @keys_ds.group(:private_key).to_a.each do |element|
        if !check_for_revocation(element[:id])  # should be okay because there should be only one valid server key in database
          private_key = element[:private_key]
          public_key = element[:public_key]
          return [public_key, private_key]
        end
      end
    # end

      # no non-revoked key in database, creating one; todo: write a logger
      puts 'generating new host key'
      crypto = CryptoBox.new  # todo: put host key generation somewhere else where it makes sense and is executed not just by accident
      public_key, private_key = crypto.generate_keypair
      register_key('host', '127.0.0.1', private_key, public_key)
      output_host_keypair
    end


  def output_key(host)
    # outputs all known, not-revoked public keys in the key database
  end

  def check_for_revocation(key_id)
    # takes a key_id and looks it up in the keystore database table. Returns true if revoked, false if not revoked
    key_hash = @keys_ds.where(:id=>key_id).to_a
    key_hash[0][:revoked]
  end

  private



  def check_for_column(table, column)
    # returns true if the column is present in the given table
    found = false  # strangely enough it does only work when it's declared here
    @DB.schema(table).each do |element|
      if "#{element[0]}".eql? "#{column}"  # does only work when it's converted to a string, even when input is already a string
        found = true
      end
    end
    if !found  # checks whether the key was found in a database column and returns with an error
      return false
    else
      return true
    end

  end

  def hash_key(public_key)
    Base64.encode64(Digest::SHA256.digest public_key)
  end

  def setup_message_database
    puts 'setting up db...'
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :messages do
      primary_key :id  # wtf
      Datetime :time  # time when the message was received
      String :client  # client (hazewood_irc, juforum_xmpp...)
      TrueClass :private  # true if the message is private (for IRC, e.g.)
      String :sender  # client specific sender of the message
      String :message  # message; only to use if it's clear that it's just a string!
      File :attachment  # to save images and complete emails
    end
    @messages_ds = @DB[:message]  # dataset creation
    @DB.disconnect
  end

  def setup_key_database
    puts 'setting up key database'
    @DB = Sequel.sqlite
    @DB = Sequel.connect($dbpath)
    @DB.create_table? :keys do
      primary_key :id  # id
      String :description  # description of the respective key
      String :host  # contains url / whatever of the host
      String :private_key  # only contains a value if it's a local private key, otherwise nil
      String :public_key  # contains public key of respectiv host
      TrueClass :revoked  # false if the key is revoked
    end
  end

  def add_new_messages_column(public_key)
    # adds a new column consisting of base64 encoded SHA256 of the public key of the remote device
    new_column_title = hash_key(public_key)
    @DB.alter_table :messages do
      add_column new_column_title, :text
    end
  end

  def delete_messages_column(column_title)
    @DB.alter_table :messages do
      drop_column column_title
    end
  end
end

class EncryptedAdapter
  def initialize

  end

  def write_encrypted_message(timestamp, client, private_bool, sender, message, attachment)
    # a drop-in encryption-enabling wrapper for DatabaseBox
    # encrypts every message's sender, message and attachments with every single pubkey in the key database

    db = Database.new
    db.write_message_to_database(timestamp, client, private_bool, enc_sender, enc_message, enc_attachment)

  end
end

class CryptoBox
  # attr_writer :pri  vate_key, :public_key
  attr_accessor :private_key, :public_key

  def initialize
    @public_key
    @private_key
  end

  def generate_keypair
    @public_key, @private_key = NaCl.crypto_box_keypair
  end

  def encrypt_sting(string_to_encrypt, receiver_key)
    nonce = SecureRandom.random_bytes(NaCl::BOX_NONCE_LENGTH)
    cipher_text = NaCl.crypto_box(string_to_encrypt, nonce, receiver_key, @private_key)
    [cipher_text, nonce]
  end

  def decrypt_string(string_to_decrypt, sender_key, nonce)
    NaCl.crypto_box_open(string_to_decrypt, nonce, sender_key, @private_key)
  end

end

db = DatabaseBox.new
db.write_message_to_database(Time.now, 'email', false, 'me', 'Hurz', nil)
db.read_messages_from_database

# db.read_messages_from_database
#db.write_

# db.register_key('blah', 'host', 'private key', 'public key')
# irc = RelayChat.new('asdfj', 'aksdjflö', 'irc.freenode.org', '#asdfjhasdkjfh')

a, b = db.output_host_keypair
