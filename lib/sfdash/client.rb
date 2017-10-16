module Sfdash
  class Client
    attr_reader :client
    attr_reader :headers
    attr_reader :tag_style
    attr_accessor :logger

    # The partner.wsdl is used by default but can be changed by passing in a new :wsdl option.
    # A client_id can be
    def initialize(options = {})
      @describe_cache = {}
      @describe_layout_cache = {}
      @headers = {}

      @wsdl = options[:wsdl] || File.dirname(__FILE__) + '/../../resources/wsdl.xml'

      # If a client_id is provided then it needs to be included
      # in the header for every request.  This allows ISV Partners
      # to make SOAP calls in Professional/Group Edition organizations.

      client_id = options[:client_id] || Sfdash.configuration.client_id
      @headers = { 'tns:CallOptions' => { 'tns:client' => client_id } } if client_id

      @version = options[:version] || Sfdash.configuration.version || 36.0
      @host = options[:host] || 'login.salesforce.com'
      @login_url = options[:login_url] || "https://#{@host}/services/Soap/u/#{@version}"

      @logger = options[:logger] || false
      # Due to SSLv3 POODLE vulnerabilty and disabling of TLSv1, use TLSv1_2
      # @ssl_version = options[:ssl_version] || :TLSv1_2
      @ssl_version = options[:ssl_version] || :TLSv1_2

      if options[:tag_style] == :raw
        @tag_style = :raw
        @response_tags = lambda { |key| key }
      else
        @tag_style = :snakecase
        @response_tags = lambda { |key| key.snakecase.to_sym }
      end

      # Override optional Savon attributes
      savon_options = {}
      %w(read_timeout open_timeout proxy raise_errors).each do |prop|
        key = prop.to_sym
        savon_options[key] = options[key] if options.key?(key)
      end

      @client = Savon.client({
        wsdl: @wsdl,
        soap_header: @headers,
        convert_request_keys_to: :none,
        convert_response_tags_to: @response_tags,
        pretty_print_xml: true,
        logger: @logger,
        log: (@logger != false),
        endpoint: @login_url,
        ssl_version: @ssl_version # Sets ssl_version for HTTPI adapter
      }.update(savon_options))
    end

    # Public: Get the names of all wsdl operations.
    # List all available operations from the partner.wsdl
    def operations
      @client.operations
    end

    # Public: Get the names of all wsdl operations.
    #
    # Supports a username/password (with token) combination or session_id/server_url pair.
    #
    # Examples
    #
    #   client.login(username: 'test', password: 'password_and_token')
    #   # => {...}
    #
    #   client.login(session_id: 'abcd1234', server_url: 'https://na1.salesforce.com/')
    #   # => {...}
    #
    # Returns Hash of login response and user info
    def login(options={})
      result = nil
      if options[:username] && options[:password]
        response = @client.call(:login) do |locals|
          locals.message :username => options[:username], :password => options[:password]
        end

        result = response.to_hash[key_name(:login_response)][key_name(:result)]

        @session_id = result[key_name(:session_id)]
        @server_url = result[key_name(:server_url)]
        $sesid = @session_id
        $surl= @server_url
      elsif options[:session_id] && options[:server_url]
        @session_id = options[:session_id]
        @server_url = options[:server_url]
      else
        raise ArgumentError.new("Must provide username/password or session_id/server_url.")
      end

      @headers = @headers.merge({"tns:SessionHeader" => {"tns:sessionId" => @session_id}})

      @client = Savon.client(
        wsdl: @wsdl,
        soap_header: @headers,
        convert_request_keys_to: :none,
        convert_response_tags_to: @response_tags,
        logger: @logger,
        log: (@logger != false),
        endpoint: @server_url,
        ssl_version: @ssl_version # Sets ssl_version for HTTPI adapter
      )

      # If a session_id/server_url were passed in then invoke get_user_info for confirmation.
      # Method missing to call_soap_api
      result = self.get_user_info if options[:session_id]

      result
    end
    alias_method :authenticate, :login


    # Public: Get the names of all sobjects on the org.
    #
    # Examples
    #
    #   # get the names of all sobjects on the org
    #   client.list_sobjects
    #   # => ['Account', 'Lead', ... ]
    #
    # Returns an Array of String names for each SObject.
    def list_sobjects
      response = describe_global # method_missing
      response[key_name(:sobjects)].collect { |sobject| sobject[key_name(:name)] }
    end

    # Public: Get the current organization's Id.
    #
    # Examples
    #
    #   client.org_id
    #   # => '00Dx0000000BV7z'
    #
    # Returns the String organization Id
    def org_id
      object = query('SELECT Id FROM Organization').first
      object.Id if object
    end

    # Public: Returns a detailed describe result for the specified sobject
    #
    # sobject - String name of the sobject.
    #
    # Examples
    #
    #   # get the describe for the Account object
    #   client.describe('Account')
    #   # => { ... }
    #
    #   # get the describe for the Account object
    #   client.describe(['Account', 'Contact'])
    #   # => { ... }
    #
    # Returns the Hash representation of the describe call.
    def describe(sobject_type)
      if sobject_type.is_a?(Array)
        response = call_soap_api(:describe_s_objects, sObjectType: sobject_type)
      else
        # Cache objects to avoid repeat lookups.
        if @describe_cache[sobject_type].nil?
          response = call_soap_api(:describe_s_object, sObjectType: sobject_type)
          @describe_cache[sobject_type] = response
        else
          response = @describe_cache[sobject_type]
        end
      end

      response
    end

    # Public: Returns the layout for the specified object
    #
    # sobject - String name of the sobject.
    #
    # Examples
    #
    #   # get layouts for an sobject type
    #   client.describe_layout('Account')
    #   # => { ... }
    #
    #   # get layouts for an sobject type
    #   client.describe_layout('Account', '012000000000000AAA')
    #   # => { ... }
    #
    # Returns the Hash representation of the describe call.
    def describe_layout(sobject_type, layout_id=nil)
      # Cache objects to avoid repeat lookups.
      @describe_layout_cache[sobject_type] ||={}

      # nil key is for full object.
      if @describe_layout_cache[sobject_type][layout_id].nil?
        response = call_soap_api(:describe_layout, :sObjectType => sobject_type, :recordTypeIds => layout_id)
        @describe_layout_cache[sobject_type][layout_id] = response
      else
        response = @describe_layout_cache[sobject_type][layout_id]
      end

      response
    end

    def query(soql)
      call_soap_api(:query, {:queryString => soql})
    end

    # Includes deleted (isDeleted) or archived (isArchived) records
    def query_all(soql)
      call_soap_api(:query_all, {:queryString => soql})
    end

    def query_more(locator)
      call_soap_api(:query_more, {:queryLocator => locator})
    end

    def search(sosl)
      call_soap_api(:search, {:searchString => sosl})
    end

    # Public: Finds a single record and returns all fields.
    #
    # sobject - The String name of the sobject.
    # id      - The id of the record. If field is specified, id should be the id
    #           of the external field.
    # field   - External ID field to use (default: nil).
    #
    # Returns Hash of sobject record.
    def find(sobject, id, field=nil)
      if field.nil? || field.downcase == "id"
        retrieve(sobject, id)
      else
        find_by_field(sobject, id, field)
      end
    end

    # Public: Finds record based on where condition and returns all fields.
    #
    # sobject - The String name of the sobject.
    # where   - String where clause or Hash made up of field => value pairs.
    # select  - Optional array of field names to return.
    #
    # Returns Hash of sobject record.
    def find_where(sobject, where={}, select_fields=[])

      if where.is_a?(String)
        where_clause = where
      elsif where.is_a?(Hash)
        conditions = []
        where.each {|k,v|
          # Wrap strings in single quotes.
          v = v.is_a?(String) ? "'#{v}'" : v
          v = 'NULL' if v.nil?

          # Handle IN clauses when value is an array.
          if v.is_a?(Array)
            # Wrap single quotes around String values.
            values = v.map {|s| s.is_a?(String) ? "'#{s}'" : s}.join(", ")
            conditions << "#{k} IN (#{values})"
          else
            conditions << "#{k} = #{v}"
          end
        }
        where_clause = conditions.join(" AND ")

      end

      # Get list of fields if none were specified.
      if select_fields.empty?
        field_names = field_list(sobject)
      else
        field_names = select_fields
      end

      soql = "SELECT #{field_names.join(", ")} FROM #{sobject} WHERE #{where_clause}"
      query(soql)
    end

    # Public: Finds a single record and returns all fields.
    #
    # sobject - The String name of the sobject.
    # id      - The id of the record. If field is specified, id should be the id
    #           of the external field.
    # field   - External ID field to use.
    #
    # Returns Hash of sobject record.
    def find_by_field(sobject, id, field_name)
      field_details = field_details(sobject, field_name)
      field_names = field_list(sobject).join(", ")

      if ["int", "currency", "double", "boolean", "percent"].include?(field_details[key_name(:type)])
        search_value = id
      else
        # default to quoted value
        search_value = "'#{id}'"
      end

      soql = "SELECT #{field_names} FROM #{sobject} WHERE #{field_name} = #{search_value}"
      result = query(soql)
      # Return first query result.
      result ? result.first : nil
    end

    # Public: Finds a single record and returns all fields.
    #
    # sobject - The String name of the sobject.
    # id      - The id of the record. If field is specified, id should be the id
    #           of the external field.
    #
    # Returns Hash of sobject record.
    def retrieve(sobject, id)
      ids = id.is_a?(Array) ? id : [id]
      call_soap_api(:retrieve, {fieldList: field_list(sobject).join(","), sObjectType: sobject, ids: ids})
    end

    # Helpers

    def field_list(sobject)
      description = describe(sobject)
      name_key = key_name(:name)
      description[key_name(:fields)].collect {|c| c[name_key] }
    end

    def field_details(sobject, field_name)
      description = describe(sobject)
      fields = description[key_name(:fields)]
      name_key = key_name(:name)
      fields.find {|f| field_name.downcase == f[name_key].downcase }
    end

    # Supports the following No Argument methods:
    #   describe_global
    #   describe_softphone_layout
    #   describe_tabs
    #   get_server_timestamp
    #   get_user_info
    #   logout
    def method_missing(method, *args)
      call_soap_api(method, *args)
    end

    def key_name(key)
      if @tag_style == :snakecase
        key.is_a?(Symbol) ? key : key.snakecase.to_sym
      else
        if key.to_s.include?('_')
          camel_key = key.to_s.gsub(/\_(\w{1})/) {|cap| cap[1].upcase }
        else
          key.to_s
        end
      end
    end

    def call_soap_api(method, message_hash={})

      response = @client.call(method.to_sym) do |locals|
        locals.message message_hash
      end

      # Convert SOAP XML to Hash
      response = response.to_hash
      
      # Get Response Body
      key = key_name("#{method}Response")
      response_body = response[key]
      #puts response_body #remove
      # Grab result section if exists.
      result = response_body ? response_body[key_name(:result)] : nil

      #puts result #puts result "result" #remove

      # Raise error when response contains errors
      if result.is_a?(Hash)
        xsi_type = result[key_name(:"@xsi:type")].to_s
        if result[key_name(:success)] == false && result[key_name(:errors)]
          errors = result[key_name(:errors)]
          raise Savon::Error.new("#{errors[key_name(:status_code)]}: #{errors[key_name(:message)]}")
        elsif xsi_type.include?("sObject")
          result = SObject.new(result)
        elsif xsi_type.include?("QueryResult")
          result = QueryResult.new(result)
        else
        end
      end

      result
    end

    def sobjects_hash(sobject_type, sobject_hash)

      if sobject_hash.is_a?(Array)
        sobjects = sobject_hash
      else
        sobjects = [sobject_hash]
      end

      sobjects.map! do |obj|
        {"ins0:type" => sobject_type}.merge(obj)
      end

      {sObjects: sobjects}
    end
  end
end
