module Rapns
  class Notification < ActiveRecord::Base
    self.table_name = 'rapns_notifications'

    attr_accessible :badge, :device_token, :sound, :alert, :attributes_for_device, :expiry,:delivered,
      :delivered_at, :failed, :failed_at, :error_code, :error_description, :deliver_after, :alert_is_json, :app

    validates :app, :presence => true
    validates :device_token, :presence => true
    validates :badge, :numericality => true, :allow_nil => true
    validates :expiry, :numericality => true, :presence => true

    validates_with Rapns::DeviceTokenFormatValidator
    validates_with Rapns::BinaryNotificationValidator

    scope :ready_for_delivery, lambda { where('delivered = ? AND failed = ? AND (deliver_after IS NULL OR deliver_after < ?)', false, false, Time.now) }

    def device_token=(token)
      write_attribute(:device_token, token.delete(" <>")) if !token.nil?
    end

    def alert=(alert)
      if alert.is_a?(Hash)
        write_attribute(:alert, multi_json_dump(alert))
        self.alert_is_json = true if has_attribute?(:alert_is_json)
      else
        write_attribute(:alert, alert)
        self.alert_is_json = false if has_attribute?(:alert_is_json)
      end
    end

    def alert
      string_or_json = read_attribute(:alert)

      if has_attribute?(:alert_is_json)
        if alert_is_json?
          multi_json_load(string_or_json)
        else
          string_or_json
        end
      else
        multi_json_load(string_or_json) rescue string_or_json
      end
    end

    def attributes_for_device=(attrs)
      raise ArgumentError, "attributes_for_device must be a Hash" if !attrs.is_a?(Hash)
      write_attribute(:attributes_for_device, multi_json_dump(attrs))
    end

    def attributes_for_device
      multi_json_load(read_attribute(:attributes_for_device)) if read_attribute(:attributes_for_device)
    end

    MDM_KEY = '__rapns_mdm__'
    def mdm=(magic)
      self.attributes_for_device = { MDM_KEY => magic }
    end

    CONTENT_AVAILABLE_KEY = '__rapns_content_available__'
    def content_available=(bool)
      return unless bool
      self.attributes_for_device = { CONTENT_AVAILABLE_KEY => true }
    end

    def as_json
      json = ActiveSupport::OrderedHash.new

      if attributes_for_device && attributes_for_device.key?(MDM_KEY)
        json['mdm'] = attributes_for_device[MDM_KEY]
      else
        json['aps'] = ActiveSupport::OrderedHash.new
        json['aps']['alert'] = alert if alert
        json['aps']['badge'] = badge if badge
        json['aps']['sound'] = sound if sound

        if attributes_for_device && attributes_for_device[CONTENT_AVAILABLE_KEY]
          json['aps']['content-available'] = 1
        end

        if attributes_for_device
          non_aps_attributes = attributes_for_device.reject { |k, v| k == CONTENT_AVAILABLE_KEY }
          non_aps_attributes.each { |k, v| json[k.to_s] = v.to_s }
        end
      end

      json
    end

    def payload
      multi_json_dump(as_json)
    end

    def payload_size
      payload.bytesize
    end

    # This method conforms to the enhanced binary format.
    # http://developer.apple.com/library/ios/#documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingWIthAPS/CommunicatingWIthAPS.html#//apple_ref/doc/uid/TP40008194-CH101-SW4
    def to_binary(options = {})
      id_for_pack = options[:for_validation] ? 0 : id
      [1, id_for_pack, expiry, 0, 32, device_token, payload_size, payload].pack("cNNccH*na*")
    end


    private

    def multi_json_load(string, options = {})
      # Calling load on multi_json less than v1.3.0 attempts to load a file from disk. Check the version explicitly.
      if Gem.loaded_specs['multi_json'].version >= Gem::Version.create('1.3.0')
        MultiJson.load(string, options)
      else
        MultiJson.decode(string, options)
      end
    end

    def multi_json_dump(string, options = {})
      MultiJson.respond_to?(:dump) ? MultiJson.dump(string, options) : MultiJson.encode(string, options)
    end
  end
end
