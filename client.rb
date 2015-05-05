require_relative 'classes.rb'
require 'rest-client'
require 'json'

$server_url = 'http://localhost:4567'
$message_storage = "sqlite://client.db"
$key_id = 6  # hardcoded atm, will be changed

class Main
  def initialize

    storage = ApplicationStorage.new
    services_to_start = []

    services_to_start << Thread.new{
      auto_refresh
    }

    services_to_start << Thread.new{
      while true
        storage.show_messages
        sleep(5)
      end
    }

    services_to_start.each{ |t| t.join }
  end

  def auto_refresh
    server = ServerInteractor.new
    while true
      server.save_new_messages
      sleep(5)
    end
  end

end

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
    sender = raw_message['sender']
    message = raw_message['message']
    attachment = raw_message['attachment']

    private_key = storage.private_key
    server_pubkey = storage.get_server_public_key($server_url)
    decoded_sender = Base64.decode64(sender)

    box = RbNaCl::SimpleBox.from_keypair(server_pubkey.b, private_key.b)

    box.decrypt(decoded_sender)
    if ApplicationStorage.new.check_for_message(server_id)
      storage.save_message(server_id, time, $server_url, source, $server_url, private, box.decrypt(Base64.decode64(sender)), box.decrypt(Base64.decode64(message)), box.decrypt(Base64.decode64(attachment)))
    end

  end

  def save_new_messages
    new_messages.each do |message|
      read_message($key_id, message)
    end
  end

  def new_messages
    saved_messages = ApplicationStorage.new.saved_messages
    available_messages = list_of_messages($key_id)
    available_messages-saved_messages
  end


  def list_of_messages(key_id)
    JSON.parse(RestClient.get "#{$server_url + '/' + key_id.to_s + '/all'}")
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

  def check_for_message(server_id)
    @messages.where(:server_id => server_id).to_a.length == 0
  end

  def save_message(server_id, time, server, source,  description, private, sender, message, attachment)
    @messages.insert(:server_id => server_id, :time => time, :server => server, :source => source, :description => description, :private => private, :sender => sender, :message => message, :attachment => attachment)
  end

  def show_messages
    @messages.to_a.each do |message|
      puts message[:time].to_s + ' ' + message[:sender] + ' @ <' + message[:source].to_s + '>: ' + message[:message]
    end
  end
  def get_server_public_key(host_url)
    key = @keys.where(:host=>host_url).exclude(:revoked=>true).to_a
    if key.length == 0
      save_server_public_key(host_url, host_url)
    end
   Base64.decode64(key[0][:public_key].split('\n')[0]).b
  end

  def saved_messages
    results = []
    @messages.to_a.each do |entry|
      results << entry[:server_id]
    end
    return results
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
    @keys.exclude(:private_key => nil).exclude(:revoked => true).to_a[0]  # does only honor the first non-revoked keypair in database
  end

  def get_local_private_key
    get_local_keypair[:public_key]
  end

  def private_key
    get_local_keypair[:private_key]
  end

  def check_local_keypair
  end

end


# connection = ServerInteractor.new
# puts connection.read_message(3, 10)

# ServerInteractor.new.read_message(6, 87) #!!!
# puts ServerInteractor.new.save_new_messages


# puts CryptoBox.new.generate_keypair[1].class


 # puts ApplicationStorage.new.get_server_public_key($server_url).encoding

# puts ApplicationStorage.new.get_server_public_key($server_url)

# puts Base64.encode64(ApplicationStorage.new.get_local_private_key)

# puts ApplicationStorage.new.check_for_message(82)

# puts ServerInteractor.new.list_of_messages(3).sort

Main.new