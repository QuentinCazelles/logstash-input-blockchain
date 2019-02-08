# encoding: utf-8
require 'logstash/inputs/protocols/protocol'
require 'date'
require 'ethereum.rb/lib/ethereum/decoder'
require 'ethereum.rb/lib/ethereum/abi'
require "sha3-pure-ruby"

require 'ethereum.rb/lib/ethereum/encoder'

class EthereumProtocol < BlockchainProtocol

  BLOCK_NUM_KEYS = %w(number difficulty totalDifficulty size gasLimit gasUsed timestamp)
  TX_NUM_KEYS = %w(nonce blockNumber transactionIndex gasPrice gas)
  
  @@decoder = Ethereum::Decoder.new

  def initialize(host, port, user, pass, logger, deployee_contract, deployer_contract, events_watched, network_id)
    super(host, port, nil, nil, logger)
    @deployee_contract = deployee_contract
    @deployer_contract = deployer_contract
    @events_watched = events_watched
    @network_id = network_id
    @events_watched_keccaked = []
    @events_watched.each { |event_name|
      @events_watched_keccaked.push(get_event_signature(event_name))
    }
  end

  # returns a JSON body to be sent to the Ethereum JSON-RPC endpoint
  def get_post_body(name, params)
    { 'method' => name, 'params' => params, 'id' => '1', 'jsonrpc' => '2.0' }
  end

  # returns the latest block number
  public
  def get_block_count
    begin
      make_rpc_call('eth_blockNumber').to_decimal
    rescue JSONRPCError, java.lang.Exception => e
      @logger.warn? && @logger.warn('Could not find latest block count', :exc => e)
    end
  end

  # returns the block at the given height
  public
  def get_block(height)     
    # get the block data
    block_data = make_rpc_call('eth_getBlockByNumber', hexprefix(height), true)
    
    return nil, nil, nil if block_data == nil

    # get all transaction data
    tx_info = block_data.delete('transactions')

    # unhex numbers and strings
    unhex(block_data, BLOCK_NUM_KEYS)
    tx_info.each do |tx|
      unhex(tx, TX_NUM_KEYS)
    end

    timestamp = Time.at(block_data['timestamp']).utc.to_datetime.iso8601(3)
      
    return block_data, tx_info, timestamp
  end # def get_block
  
  def get_signature_from_name_types(event_name, event_types)
    tmp = event_name + '('
    event_types.each { |name, type|
     tmp += type + ','
    }
    tmp.chop() + ')'
  end

  def unhex(data, num_keys)
    data.each do |key, value|
      next if value.nil? or value.kind_of?(Array)
  
      if num_keys.include? key
           if(value.methods.include? :to_decimal)
                 data[key] = value.to_decimal()
           end
#      else
#           if(value.methods.include? :to_string)
#                data[key] = value.to_string()
#           end
      end
    end
  end
  
  def hexprefix(param)
    return '0x' + param.to_s
  end
  
  def get_tx_receipt(tx_hash)
    make_rpc_call('eth_getTransactionReceipt', tx_hash)
  end
  
  def keccak256(string)
    Digest::SHA3.hexdigest(string, 256)
  end
  
  def get_deployee_infos(tx_info)
    tx_receipt = get_tx_receipt(tx_info['hash'])
    if tx_receipt['to'].to_s != get_address(@deployer_contract)
      return nil
    end
    tx_receipt['logs'].each {|log|
      topics_include_event = false
      log['topics'].each { |topic|
        if @events_watched_keccaked.include?(topic)
          topics_include_event = true
          break
        end
      }
      if topics_include_event
        deployee_address = hexprefix(decode_data("address", log['data']))          
        infos = Hash.new
        get_contract_abi(@deployee_contract).each { |entity|
          infos = infos.merge(read_abi_entity_properties(entity, deployee_address))
        }
        get_contract_abi(@deployer_contract).each { |entity|
          infos = infos.merge(read_abi_entity_functions(entity, deployee_address))
        }
        infos['address'] = deployee_address
        return infos
      end
    }
    nil
  end
  
  def read_abi_entity_properties(entity, contract_address = nil)
    if contract_address == nil
      contract_address = get_address(@deployer_contract)
    end
    infos = Hash.new
    if entity['constant'] && entity['inputs'].length == 0
      property_type = entity['outputs'][0]['type']
      property_name = entity['name']
      infos[property_name] = get_property(property_type, property_name, contract_address)
    end
    infos
  end
  
  def read_abi_entity_functions(entity, deployee_address)
    infos = Hash.new
    if entity.has_key?('inputs') && entity['inputs'].length == 1 && entity.has_key?('outputs') && entity['outputs'].length == 1  && entity['inputs'][0]['type'] == "address"
      function_label = entity['name']
      property_name = entity['outputs'][0]['name']
      property_type = entity['outputs'][0]['type']
      infos[property_name] = get_function_return(function_label, get_address(@deployer_contract), { "address" => deployee_address }, property_type)
    end
    infos
  end
  
  def get_return_type(function, contract)
    get_contract_abi(contract).each { |entity|
      if entity['name'] == function
        return entity['outputs'][0]['type']
      end
    }
    nil
  end
  
  def get_return_name(function, contract)
    get_contract_abi(contract).each { |entity|
      if entity['name'] == function
        return entity['outputs'][0]['name']
      end
    }
    nil
  end
  
  def get_contract_abi(contract)
    get_contract_obj(contract)['abi']
  end
  
  def get_function_return(function_label, contract_address, arguments, return_type)
    input_data = function_label + '('
    input_data_args = ""
    arguments.each { |arg_type, arg_value|
      input_data += arg_type + ','
      arg_tmp = ""
      if arg_type == "address"
        arg_tmp = arg_value.to_s[2..42]
        while arg_tmp.length != 64 do
          arg_tmp = '0' + arg_tmp
        end
      end
      input_data_args += arg_tmp
    }
    input_data = input_data.chop()
    input_data += ')'
    input_data = hexprefix(keccak256(input_data))
    input_data = input_data[0, 10]
    input_data += input_data_args    
    result = make_rpc_call('eth_call', {"to" => contract_address, "data" => input_data}, "latest")      
    decoded = decode_data(return_type, result)
    if return_type == "address"
      return hexprefix(decoded)
    end
    decoded
  end
  
  def get_property(property_type, property_name, contract_address)
    function_signature = hexprefix(keccak256(property_name + '()'))
    input_data = function_signature[0, 10]
    result = make_rpc_call('eth_call', {"to" => contract_address, "data" => input_data}, "latest")
    decoded = decode_data(property_type, result)
    if property_type == "address"
      return hexprefix(decoded)
    end
    decoded
  end
  
  def decode_data(data_type, data, data_start = 0)
    @@decoder.decode(data_type, data, data_start)
  end
  
  def get_event_signature(event_name)
    event_types = get_event_types(event_name)
    event_signature = event_name + '('
    event_types.each { |name, type|
      event_signature += type + ','
    }
    event_signature = event_signature.chop() + ')'
    hexprefix(keccak256(event_signature))
  end
  
  def get_address(contract)
    get_contract_obj(contract)['networks'][@network_id.to_s]['address']
  end
  
  def get_contract_obj(contract)
    JSON.parse(File.read(@@path + contract + ".json"))
  end
  
  def get_event_types(event_name)
    data_types = Hash.new
    data_hash = JSON.parse(File.read(@@path + @deployer_contract + ".json"))
    data_hash['abi'].each do |element|
      if element['type'] == "event" && element['name'] == event_name
        element['inputs'].each do |field|
          data_types[field['name']] = field['type']
        end
      end
    end
    data_types
  end

end

class String
  def to_decimal
    self.convert_base(16, 10)
  end

  def to_string
    length_before = self.length
    conv = self.convert_base(16, 16)
    while length_before == 66 && conv.length != 64 do
      conv = '0' + conv
    end
    conv
  end

  def convert_base(from, to)
    conv = self.to_i(from).to_s(to)
    to == 10 && conv.to_i <= 9223372036854775807 ? conv.to_i : conv
  end
end
