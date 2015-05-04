require_relative 'classes.rb'
require 'rest-client'
require 'json'

$server_url = 'http://localhost:4567'
$message_storage = "sqlite://client.db"

$private_key_file = ENV['HOME']+'/.rubin/private_key'
$public_key_file  = ENV['HOME']+'/.rubin/public_key'
class ServerInteractor
  def initialize
  end

  def read_server_key
    Base64.decode64(RestClient.get "#{$server_url + '/key'}")
  end

  def read_message(key_id, message_id)
    raw_message = JSON.parse(RestClient.get "#{$server_url + '/' + key_id.to_s + '/' + message_id.to_s}")
    storage = ApplicationStorage.new
    server_id = raw_message['id']
    time = raw_message['time']
    source = raw_message['client']
    private = raw_message['private']
    sender_decode = Base64.decode64(raw_message['sender']).b
    puts raw_message['sender']
    puts sender_decode
    message_decode = Base64.decode64(raw_message['message'].split('\n')[0]).b
    attachment_decode = Base64.decode64(raw_message['attachment'].split('\n')[0]).b
    private_key = storage.private_key
    server_pubkey = storage.get_server_public_key($server_url)
    sender = CryptoBox.new.decrypt_string(sender_decode, private_key, server_pubkey)
    message = CryptoBox.new.decrypt_string(message_decode, storage.private_key, storage.get_server_public_key($server_url))
    attachment = CryptoBox.new.decrypt_string(raw_message['attachment'], storage.private_key, storage.get_server_public_key($server_url))

    storage.save_message(server_id, time, $server_url, source, $server_url, private, sender, message, attachment)
  end

  def save_message(key_id, message_id)
    read_message(key_id, message_id)
  end
end

##
# stores messages and keys

class ApplicationStorage
  def initialize
    @AS
    @AS = Sequel.sqlite
    @AS = Sequel.connect($message_storage)
    @AS.create_table? :keys do
      primary_key :id  # id
      String :description  # description of the respective key
      String :host  # contains url / whatever of the host
      String :private_key  # only contains a value if it's a local private key, otherwise nil
      String :public_key  # contains public key of respectiv host
      TrueClass :revoked  # false if the key is revoked
    end
    @keys = @AS[:keys]  # dataset for the key table
    @AS.disconnect

    @AS = Sequel.sqlite
    @AS = Sequel.connect($message_storage)
    @AS.create_table? :messages do
      primary_key :id
      Integer :server_id
      Daytime :time
      String :server  # url of the server
      String :source  # called client on the server
      String :description  # verbose description of this server
      TrueClass :private
      String :sender
      String :message
      File :attachment
    end

    @AS.disconnect
    @AS = Sequel.sqlite
    @AS = Sequel.connect($message_storage)


    @messages = @AS[:messages]

    if @keys.exclude(:private_key => nil).exclude(:revoked => true).to_a.length.eql?(0)
      keypair = CryptoBox.new.generate_keypair
      pub = keypair[0].to_s
      priv = keypair[1].to_s
      @keys.insert(:description => 'local key', :host => 'localhost', :private_key => priv, :public_key => pub, :revoked => false)
    end


  end


  def save_message(server_id, time, server, source,  description, private, sender, message, attachment)
    @messages.insert(:server_id => server_id, :time => time, :server => server, :source => source, :description => description, :private => private, :sender => sender, :message => message, :attachment => attachment)
  end

  def get_server_public_key(host_url)
    key = @keys.where(:host=>host_url).exclude(:revoked=>true).to_a
    if key.length == 0
      save_server_public_key(host_url, host_url)
    end
   Base64.decode64(key[0][:public_key].split('\n')[0]).b
  end

  def read_server_public_key(host_url)
    found_server_key = @keys.where(:host=>host_url).exclude(:revoked=>true).to_a
    if found_server_key.length < 1
      # no keypair could be found
      return nil
    elsif found_server_key.length > 1
      # more than one keypair could be found
      return nil
    elsif found_server_key.eql?(1)
      return found_server_key
    else
      # wtf?
    end
  end

  def save_server_public_key(server_name, server_url)
    server = ServerInteractor.new
    @keys.insert(:description => server_name, :host => server_url, :private_key => nil, :public_key => server.read_server_key, :revoked => false)
  end

  def get_local_keypair
    found_keys = @keys.exclude(:private_key => nil).exclude(:revoked => true).to_a[0]  # does only honor the first non-revoked keypair in database
  end

  def private_key
    get_local_keypair[:private_key]
  end

  def check_local_keypair
  end

end


# connection = ServerInteractor.new
# puts connection.read_message(3, 10)

puts ServerInteractor.new.read_message(3, 10)

# puts CryptoBox.new.generate_keypair[1].class


 # puts ApplicationStorage.new.get_server_public_key($server_url).encoding
