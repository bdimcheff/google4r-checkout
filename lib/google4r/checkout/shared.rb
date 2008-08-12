#--
# Project:   google4r
# File:      lib/google4r/checkout/shared.rb 
# Author:    Manuel Holtgrewe <purestorm at ggnore dot net>
# Copyright: (c) 2007 by Manuel Holtgrewe
# License:   MIT License as follows:
#
# Permission is hereby granted, free of charge, to any person obtaining 
# a copy of this software and associated documentation files (the 
# "Software"), to deal in the Software without restriction, including 
# without limitation the rights to use, copy, modify, merge, publish, 
# distribute, sublicense, and/or sell copies of the Software, and to permit
# persons to whom the Software is furnished to do so, subject to the 
# following conditions:
#
# The above copyright notice and this permission notice shall be included 
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF 
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY 
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
# OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
#++
# This file contains the classes and modules that are shared by the notification
# handling and parsing as well as the command generating code.

#--
# TODO: Make the optional attributes return defaults that make sense, i.e. Money.new(0)?
#++
module Google4R #:nodoc:
  module Checkout #:nodoc:
    # This exception is thrown by Command#send_to_google_checkout when an error occured.
    class GoogleCheckoutError < Exception
      # The serial number of the error returned by Google.
      attr_reader :serial_number
      
      # The HTTP response code of Google's response.
      attr_reader :response_code
      
      # The parameter is a hash with the entries :serial_number, :message and :response_code. 
      # The attributes serial_number, message and response_code are set to the values in the 
      # Hash.
      def initialize(hash)
        @response_code = hash[:response_code]
        @message = hash[:message]
        @serial_number = hash[:serial_number]
      end
      
      # Returns a human readable representation of the Exception with the message, HTTP 
      # response code and serial number as returned by Google checkout.
      def to_s
        "GoogleCheckoutError: message = '#{@message}', response code = '#{@response_code}', serial number = '#{@serial_number}'."
      end
    end

    # ShoppingCart instances are containers for Item instances. You can add
    # Items to the class using #create_item (see the documentation of this
    # method for an example).
    class ShoppingCart
      # The owner of this cart. At the moment, this always is the CheckoutCartCommand.
      attr_reader :owner
      
      # The items in the cart. Do not modify this array directly but use
      # #create_item to add items.
      attr_reader :items
      
      # You can set the <cart-expiration> time with this property. If left
      # unset then the tag will not be generated and the cart will never
      # expire.
      attr_accessor :expires_at
      
      # You can set almost arbitrary data into the cart using this method.
      #
      # The data will be converted to XML in the following way: The keys are converted
      # to tag names (whitespace becomes "-", all chars not matching /[a-zA-Z0-9\-_])/
      # will be removed.
      #
      # If a value is an array then the key for this value will be used as the tag
      # name for each of the arrays's entries.
      #
      # Arrays will be flattened before it is processed.
      #
      # === Example
      #
      #   cart.private_data = { 'foo' => { 'bar' => 'baz' } })
      #   
      #   # will produce the following XML
      #
      #   <foo>
      #     <bar>baz</bar>
      #   </foo>
      #
      #
      #   cart.private_data = { 'foo' => [ { 'bar' => 'baz' }, "d'oh", 2 ] }
      #   
      #   # will produce the following XML
      #
      #   <foo>
      #     <bar>baz</bar>
      #   </foo>
      #   <foo>d&amp;</foo>
      #   <foo>2</foo>
      attr_reader :private_data
      
      # Sets the value of the private_data attribute.
      def private_data=(value)
        raise "The given value #{value.inspect} is not a Hash!" unless value.kind_of?(Hash)
        @private_data = value
      end
      
      # Initialize a new ShoppingCart with an empty Array for the items.
      def initialize(owner)
        @owner = owner
        @items = Array.new
      end
      
      # Use this method to add a new item to the cart. If you use a block with
      # this method then the block will be given the new item. The new item 
      # will be returned in any case.
      #
      # Passing a block is the preferred way of using this method.
      #
      # === Example
      #
      #   # Using a block (preferred).
      #   cart = ShoppingCart.new
      #   
      #   cart.create_item do |item|
      #     item.name = "Dry Food Pack"
      #     item.description = "A pack of highly nutritious..."
      #     item.unit_price = Money.new(3500, "USD") # $35.00
      #     item.quantity = 1
      #   end
      #   
      #   # Not using a block.
      #   cart = ShoppingCart.new
      #   
      #   item = cart.create_item
      #   item.name = "Dry Food Pack"
      #   item.description = "A pack of highly nutritious..."
      #   item.unit_price = Money.new(3500, "USD") # $35.00
      #   item.quantity = 1
      def create_item(&block)
        item = Item.new(self)
        @items << item

        # Pass the newly generated item to the given block to set its attributes.
        yield(item) if block_given?
        
        return item
      end

      # Creates a new ShoppingCart object from a REXML::Element object.
      def self.create_from_element(element, owner)
        result = ShoppingCart.new(owner)
        
        text = element.elements['cart-expiration/good-until-date'].text rescue nil
        result.expires_at = Time.parse(text) unless text.nil?
        
        data_element = element.elements['merchant-private-data']
        value = PrivateDataParser.element_to_value(data_element) unless data_element.nil?
        
        result.private_data = value unless value.nil?
        
        element.elements.each('items/item') do |item_element|
          result.items << Item.create_from_element(item_element, result)
        end
        
        return result
      end
    end

    # An Item object represents a line of goods in the shopping cart/receipt.
    #
    # You should never initialize them directly but use ShoppingCart#create_item instead.
    #
    # Note that you have to create/set the tax tables for the owner of the cart in which
    # the item is before you can set the tax_table attribute.
    class Item
      # The cart that this item belongs to.
      attr_reader :shopping_cart
      
      # The name of the cart item (string, required).
      attr_accessor :name
      
      # The description of the cart item (string, required).
      attr_accessor :description
      
      # The price for one unit of the given good (Money instance, required).
      attr_reader :unit_price

      # Sets the price for one unit of goods described by this item. money must respond to
      # :cents and :currency as the Money class does.
      def unit_price=(money)
        if not (money.respond_to?(:cents) and money.respond_to?(:currency)) then
          raise "Invalid price - does not respond to :cents and :currency - #{money.inspect}."
        end
        
        @unit_price = money
      end
      
      # The weigth of the cart item (Weight, required when carrier calculated
      # shipping is used)
      attr_reader :weight
      
      # Sets the weight of this item
      def weight=(weight)
        raise "Invalid object type for weight" unless weight.kind_of? Weight
        @weight = weight
      end
      
      
      # Number of units that this item represents (integer, required).
      attr_accessor :quantity
      
      # Optional string value that is used to store the item's id (defined by the merchant) 
      # in the cart. Serialized to <merchant-item-id> in XML. Displayed by Google Checkout.
      attr_accessor :id
      
      # Optional hash value that is used to store the item's id (defined by the merchant) 
      # in the cart. Serialized to <merchant-private-item-data> in XML. Not displayed by
      # Google Checkout.
      #
      # Must be a Hash. See ShoppingCart#private_data on how the serialization to XML is
      # done.
      attr_reader :private_data

      # Sets the private data for this item. 
      def private_data=(value)
        raise "The given value #{value.inspect} is not a Hash!" unless value.kind_of?(Hash)
        @private_data = value
      end
      
      # The tax table to use for this item. Optional.
      attr_reader :tax_table
      
      # Sets the tax table to use for this item. When you set this attribute using this
      # method then the used table must already be added to the cart. Otherwise, a 
      # RuntimeError will be raised.
      def tax_table=(table)
        raise "The table #{table.inspect} is not in the item's cart yet!" unless shopping_cart.owner.tax_tables.include?(table)
        
        @tax_table = table
      end
      
      # DigitalContent information for this item. Optional.
      attr_reader :digital_content
      
      def create_digital_content(digital_content=nil, &block)
        
        if @digital_content.nil?
          if digital_content.nil?
            @digital_content = DigitalContent.new
          else
            @digital_content = digital_content
          end
        end
        
        if block_given?
          yield @digital_content
        end
        
        return @digital_content
      end
      
      # Create a new Item in the given Cart. You should not instantize this class directly
      # but use Cart#create_item instead.
      def initialize(shopping_cart)
        @shopping_cart = shopping_cart
      end

      # Creates a new Item object from a REXML::Element object.
      def self.create_from_element(element, shopping_cart)
        result = Item.new(shopping_cart)
        
        result.name = element.elements['item-name'].text
        result.description = element.elements['item-description'].text
        result.quantity = element.elements['quantity'].text.to_i
        result.id = element.elements['merchant-item-id'].text rescue nil
        
        weight_element = element.elements['item-weight']
        if not weight_element.nil?
          result.weight = Weight.create_from_element(weight_element)
        end

        data_element = element.elements['merchant-private-item-data']
        if not data_element.nil? then
          value = PrivateDataParser.element_to_value(data_element)
          result.private_data = value unless value.nil?
        end
        
        table_selector = element.elements['tax-table-selector'].text rescue nil
        if not table_selector.nil? then
          result.tax_table = shopping_cart.owner.tax_tables.find {|table| table.name == table_selector }
        end

        unit_price = (element.elements['unit-price'].text.to_f * 100).to_i
        unit_price_currency = element.elements['unit-price'].attributes['currency']
        result.unit_price = Money.new(unit_price, unit_price_currency)
        
        digital_content_element = element.elements['digital-content']
        if not digital_content_element.nil?
          result.create_digital_content(DigitalContent.create_from_element(digital_content_element))
        end
        
        return result
      end

      # A DigitalContent item represents the information relating to online delivery of digital items
      #
      # You should never initialize it directly but use Item#digital_content instead
      #
      # See http://code.google.com/apis/checkout/developer/Google_Checkout_Digital_Delivery.html
      # for information on Google Checkout's idea of digital content.
      # 
      #   item.digital_content do |dc|
      #     dc.optimistic!
      #     dc.description = %{Here's some information on how to get your content}
      #   end
      class DigitalContent
        
        # Constants for display-disposition
        OPTIMISTIC = 'OPTIMISTIC'
        PESSIMISTIC = 'PESSIMISTIC'

        # A description of how the user should access the digital content 
        # after completing the order (string, required for description-based
        # delivery, otherwise optional)
        attr_accessor :description
        
        # Either 'OPTIMISTIC' or 'PESSIMISTIC'. If OPTIMISTIC, then Google
        # will display instructions for accessing the digital content as soon
        #as the buyer confirms the order. Optional, but default is PESSIMISTIC
        attr_reader :display_disposition

        def display_disposition=(disposition)
          raise "display_disposition can only be set to PESSIMISTIC or OPTIMISTIC" unless disposition == OPTIMISTIC || disposition == PESSIMISTIC
          @display_disposition = disposition
        end

        # A boolean identifying whether email delivery is used for this item.
        attr_accessor :email_delivery

        # A key required by the user to access this digital content after completing the order (string, optional)
        attr_accessor :key

        # A URL required by the user to access this digital content after completing the order (string, optional)
        attr_accessor :url
        
        def initialize
          @display_disposition = PESSIMISTIC
        end
        
        # Creates a new DigitalContent object from a REXML::Element object
        def self.create_from_element(element)
          result = DigitalContent.new
          result.description = element.elements['description'].text rescue nil
          result.display_disposition = element.elements['display-disposition'].text rescue nil
          result.email_delivery = element.elements['email-delivery'].text rescue nil # TODO need to convert to boolean?
          result.key = element.elements['key'].text rescue nil
          result.url = element.elements['url'].text rescue nil
          return result
        end
      end
    end
    
    # A TaxTable is an ordered array of TaxRule objects. You should create the TaxRule
    # instances using #create_rule
    #
    # You must set up a tax table factory and should only create tax tables from within
    # its temporal factory method as described in the class documentation of Frontend.
    #
    # Each tax table must have one or more tax rules.
    #
    # === Example
    #
    #   include Google4R::Checkout
    #
    #   tax_free_table = TaxTable.new(false)
    #   tax_free_table.name = "default table"
    #   tax_free_table.create_rule do |rule|
    #     rule.area = UsCountryArea.new(UsCountryArea::ALL)
    #     rule.rate = 0.0
    #   end
    class TaxTable
      # The name of this tax table (string, required).
      attr_accessor :name
      
      # An Array of the TaxRule objects that this TaxTable contains. Use #create_rule do
      # add to this Array but do not change it directly.
      attr_reader :rules
      
      # Boolean, true iff the table's standalone attribute is to be set to "true".
      attr_reader :standalone
      
      def initialize(standalone)
        @rules = Array.new
        
        @standalone = standalone
      end
      
      # Use this method to add a new TaxRule to the table. If you use a block with
      # this method then the block will called with the newly created rule for the
      # parameter. The method will return the new rule in any case.
      def create_rule(&block)
        rule = TaxRule.new(self)
        @rules << rule
        
        # Pass the newly generated rule to the given block to set its attributes.
        yield(rule) if block_given?
        
        return rule
      end
    end
    
    # A TaxRule specifies which taxes to apply in which area. Have a look at the "Google
    # Checkout documentation" [http://code.google.com/apis/checkout/developer/index.html#specifying_tax_info]
    # for more information.
    class TaxRule
      # The table this rule belongs to.
      attr_reader :table
      
      # The tax rate for this rule (double, required).
      attr_accessor :rate
      
      # The area where this tax rule applies (Area subclass instance, required). Serialized
      # to <tax-area> in XML.
      attr_accessor :area

      # If shipping should be taxed with this tax rule (boolean, defaults to false)
      attr_accessor :shipping_taxed
      
      # Creates a new TaxRule in the given TaxTable. Do no call this method yourself
      # but use TaxTable#create_rule instead!
      def initialize(table)
        @table = table
        @shipping_taxed = false
      end
    end
    
    # Abstract class for areas that are used to specify a tax area. Do not use this class
    # but only its subclasses.
    class Area
      # Mark this class as abstract by throwing a RuntimeError on initialization.
      def initialize #:nodoc:
        raise "Do not use the abstract class Google::Checkout::Area!"
      end
    end

    # Instances of UsZipArea represent areas specified by US ZIPs and ZIP patterns.
    class UsZipArea < Area
      # The pattern for this ZIP area.
      attr_accessor :pattern
      
      # You can optionally initialize the Area with its value.
      def initialize(pattern=nil)
        self.pattern = pattern unless pattern.nil?
      end
    end
    
    # Instances of WorldArea represent a tax area that applies globally.
    class WorldArea < Area
      def initialize
      end
    end

    # Instances of PostalArea represent a geographical region somewhere in the world.
    class PostalArea < Area
      
      # String; The two-letter ISO 3166 country code.
      attr_accessor :country_code
      
      # String; Postal code or a range of postal codes for a specific country. To specify a 
      # range of postal codes, use an asterisk as a wildcard operator. For example, 
      # you can provide a postal_code_pattern value of "SW*" to indicate that a shipping 
      # option is available or a tax rule applies in any postal code beginning with the 
      # characters SW.
      # 
      # === Example
      # 
      # area = PostalArea.new('DE')
      # area.postal_code_pattern = '10*'
      attr_accessor :postal_code_pattern
      
      # === Parameters
      #
      # country_code should be a two-letter ISO 3166 country code
      # postal_code_pattern should be a full or partial postcode string, using * as a wildcard
      def initialize(country_code=nil, postal_code_pattern=nil)     
        @country_code = country_code
        @postal_code_pattern = postal_code_pattern
      end
    end
    
    # Instances of UsStateArea represent states in the US. 
    class UsStateArea < Area
      # The two-letter code of the US state.
      attr_reader :state
      
      # You can optionally initialize the Area with its value.
      def initialize(state=nil)
        @state = state unless state.nil?
      end
      
      # Writer for the state attribute. value must match /^[A-Z]{2,2}$/.
      def state=(value)
        raise "Invalid US state: #{value}" unless value =~ /^[A-Z]{2,2}$/
        @state = value
      end
    end
    
    # Instances of UsCountryArea identify a region within the US.
    class UsCountryArea < Area
      CONTINENTAL_48 = "CONTINENTAL_48".freeze
      FULL_50_STATES = "FULL_50_STATES".freeze
      ALL = "ALL".freeze
      
      # The area that is specified with this UsCountryArea (required). Can be
      # one of UsCountryArea::CONTINENTAL_48, UsCountryArea::FULL_50_STATES
      # and UsCountryArea::ALL.
      # See the Google Checkout API for information on these values.
      attr_reader :area

      # You can optionally initialize the Area with its value.
      def initialize(area=nil)
        self.area = area unless area.nil?
      end

      # Writer for the area attribute. value must be one of CONTINENTAL_48, 
      # FULL_50_STATES and ALL
      def area=(value)
        raise "Invalid area :#{value}!" unless [ CONTINENTAL_48, FULL_50_STATES, ALL ].include?(value)
        @area = value
      end
    end
    
    # Abstract class for delivery methods
    class DeliveryMethod
      # The name of the shipping method (string, required).
      attr_accessor :name
      
      # The price of the shipping method (Money instance, required).
      attr_reader :price
      
      # Sets the cost for this shipping method. money must respond to :cents and :currency
      # as Money objects would.
      def price=(money)
        if not (money.respond_to?(:cents) and money.respond_to?(:currency)) then
          raise "Invalid cost - does not respond to :cents and :currency - #{money.inspect}."
        end
        
        @price = money
      end
      
      # Mark this class as abstract by throwing a RuntimeError on initialization.
      def initialize
        raise "Do not use the abstract class Google::Checkout::ShippingMethod!"
      end
    end
    
    # Abstract class for shipping methods. Do not use this class directly but only
    # one of its subclasses.
    class ShippingMethod < DeliveryMethod
      # An Array of allowed areas for shipping-restrictions of this shipping instance. Use 
      # #create_allowed_area to add to this area but do not change it directly.
      attr_reader :shipping_restrictions_allowed_areas
      
      # An Array of excluded areas for shipping-restrictions of this shipping instance. Use
      # #create_excluded_area to add to this area but do not change it directly.
      attr_reader :shipping_restrictions_excluded_areas
      
      def initialize
        @shipping_restrictions_allowed_areas = Array.new
        @shipping_restrictions_excluded_areas = Array.new
      end
      
      # This method create a new instance of subclass of Area and put it
      # in the array determined by the two symbols provided.  The valid
      # symbols for the first two parameters are:
      #
      # type  : :shipping_restrictions, :address_filters
      # areas : :allowed_areas, :excluded_areas
      #
      # The third parameter clazz is used to specify the type of
      # Area you want to create.  It can be one
      # of { PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea }.
      #
      # Raises a RuntimeError if the parameter clazz is invalid.
      #
      # If you passed a block (preferred) then the block is called
      # with the Area as the only parameter.
      #
      # === Example
      #
      #    method = MerchantCalculatedShipping.new
      #    method.create_area(:shipping_restrictions, :allowed_areas, UsCountryArea) do |area|
      #       area.area = UsCountryArea::ALL
      #    end
      def create_area(type, areas, clazz, &block)
        areas_array_name = "@#{type.to_s + '_' + areas.to_s}"
        areas = instance_variable_get(areas_array_name)
        raise "Undefined instance variable: #{areas_array_name}" unless areas.nil? == false
        raise "Invalid Area class: #{clazz}!" unless [ PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea ].include?(clazz)
        area = clazz.new
        areas << area

        yield(area) if block_given?
        
        return area
      end
      
      # Creates a new Area, adds it to the internal list of allowed areas for shipping
      # restrictions. If you passed a block (preferred) then the block is called
      # with the Area as the only parameter.
      #
      # The area to be created depends on the given parameter clazz. It can be one
      # of { PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea }.
      #
      # Raises a RuntimeError if the parameter clazz is invalid.
      #
      # === Example
      #
      #    method = FlatRateShipping.new
      #    method.create_allowed_area(UsCountryArea) do |area|
      #       area.area = UsCountryArea::ALL
      #    end
      def create_allowed_area(clazz, &block)
        return create_area(:shipping_restrictions, :allowed_areas, clazz, &block)
      end
      
      # Creates a new Area, adds it to the internal list of excluded areas for shipping
      # restrictions. If you passed a block (preferred) then the block is called
      # with the Area as the only parameter. The created area is returned in any case.
      #
      # The area to be created depends on the given parameter clazz. It can be one
      # of { PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea }.
      #
      # Raises a RuntimeError if the parameter clazz is invalid.
      #
      # === Example
      #
      #    method = FlatRateShipping.new
      #    method.create_excluded_area(UsCountryArea) do |area|
      #       area.area = UsCountryArea::ALL
      #    end
      def create_excluded_area(clazz, &block)
        return create_area(:shipping_restrictions, :excluded_areas, clazz, &block)
      end
      
      alias :create_shipping_restrictions_allowed_area :create_allowed_area
      alias :create_shipping_restrictions_excluded_area :create_excluded_area
    end
    
    # A class that represents the "pickup" shipping method.
    class PickupShipping < DeliveryMethod
      def initialize
      end
    end
    
    # A class that represents the "flat_rate" shipping method.
    class FlatRateShipping < ShippingMethod
      def initialize
        super
      end
    end
    
    # A class that represents the "merchant-calculated" shipping method
    class MerchantCalculatedShipping < ShippingMethod
      
      # An Array of allowed areas for address-filters of this shipping instance. Use 
      # #create_allowed_area to add to this area but do not change it directly.
      attr_reader :address_filters_allowed_areas
      
      # An Array of excluded areas for address-filters of this shipping instance. Use
      # #create_excluded_area to add to this area but do not change it directly.
      attr_reader :address_filters_excluded_areas
      
      def initialize
        super
        @address_filters_allowed_areas = Array.new
        @address_filters_excluded_areas = Array.new
      end
      
      # Creates a new Area, adds it to the internal list of allowed areas for 
      # address filters. If you passed a block (preferred) then the block is 
      # called with the Area as the only parameter.
      #
      # The area to be created depends on the given parameter clazz. It can be one
      # of { PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea }.
      #
      # Raises a RuntimeError if the parameter clazz is invalid.
      #
      # === Example
      #
      #    method = FlatRateShipping.new
      #    method.create_allowed_area(UsCountryArea) do |area|
      #       area.area = UsCountryArea::ALL
      #    end
      def create_address_filters_allowed_area(clazz, &block)
        return create_area(:address_filters, :allowed_areas, clazz, &block)
      end
      
      # Creates a new Area, adds it to the internal list of excluded areas for 
      # address filters. If you passed a block (preferred) then the block is 
      # called with the Area as the only parameter.
      #
      # The area to be created depends on the given parameter clazz. It can be one
      # of { PostalArea, UsCountryArea, UsStateArea, UsZipArea, WorldArea }.
      #
      # Raises a RuntimeError if the parameter clazz is invalid.
      #
      # === Example
      #
      #    method = FlatRateShipping.new
      #    method.create_allowed_area(UsCountryArea) do |area|
      #       area.area = UsCountryArea::ALL
      #    end
      def create_address_filters_allowed_area(clazz, &block)
        return create_area(:address_filters, :allowed_areas, clazz, &block)
      end
    end
    
    # A class that represents the "merchant-calculated" shipping method
    class CarrierCalculatedShipping
      # This encapsulates information about all of the shipping methods 
      # for which Google Checkout should obtain shipping costs.
      attr_reader :carrier_calculated_shipping_options
      
      # This encapsulates information about all of the packages that will be
      # shipped to the buyer. At this time, merchants may only specify 
      # one package per order.
      attr_reader :shipping_packages
      
      def initialize()
        @carrier_calculated_shipping_options = Array.new
        @shipping_packages = Array.new
      end
      
      def create_carrier_calculated_shipping_option(&block)
        option = CarrierCalculatedShippingOption.new(self)
        @carrier_calculated_shipping_options << option
        
        # Pass the newly generated rule to the given block to set its attributes.
        yield(option) if block_given?
        
        return option
      end
      
      def create_shipping_package(&block)
        package = ShippingPackage.new(self)
        @shipping_packages << package
        
        # Pass the newly generated rule to the given block to set its attributes.
        yield(package) if block_given?
        
        return package
      end
      
      # Creates a new CarrierCalculatedShipping from the given
      # REXML::Element instance.
      # For testing only.
      def create_from_element(element)
        result = CarrierCalculatedShipping.new
        element.elements.each('carrier-calculated-shipping-options/carrier-calculated-shipping-option') do |shipping_option_element|
          result.carrier_calculated_shipping_options << CarrierCalculatedShippingOption.create_from_element(self, shipping_option_element)
        end
        element.elements.each('shipping-packages/shipping-package') do |shipping_package_element|
          result.shipping_packages << ShippingPackage.create_from_element(self, shipping_package_element)
        end
      end
      
      class CarrierCalculatedShippingOption < DeliveryMethod
        # Constants for shipping company
        FEDEX = 'FedEx'
        UPS = 'UPS'
        USPS = 'USPS'
        
        # Constants for carrier pickup
        DROP_OFF = 'DROP_OFF'
        REGULAR_PICKUP = 'REGULAR_PICKUP'
        SPECIAL_PICKUP = 'SPECIAL_PICKUP'  
        
        # The CarrierCalculatedShipping instance that this option belongs to.
        attr_reader :carrier_calculated_shipping
        
        # The name of the company that will ship the order.
        # The only valid values for this tag are FedEx, UPS and USPS.
        # (String, required)
        alias :shipping_company :name
        alias :shipping_company= :name=
        
        # The shipping option that is being offered to the buyer
        attr_accessor :shipping_type
       
        # This specifies how the package will be transferred from the merchant
        # to the shipper. Valid values for this tag are REGULAR_PICKUP, 
        # SPECIAL_PICKUP and DROP_OFF. The default value for this tag is DROP_OFF.
        # (optional)
        attr_accessor :carrier_pickup
        
        # The fixed charge that will be added to the total cost of an order
        # if the buyer selects the associated shipping option
        # (Money, optional)
        attr_accessor :additional_fixed_charge
        
        # The percentage amount by which a carrier-calculated shipping rate
        # will be adjusted. The tag's value may be positive or negative.
        # (Float, optional)
        attr_accessor :additional_variable_charge_percent
        
        def initialize(carrier_calculated_shipping)
          @carrier_calculated_shipping = carrier_calculated_shipping
          #@carrier_pickup = DROP_OFF
        end
        
        # Creates a new CarrierCalculatedShippingOption from the given
        # REXML::Element instance.
        # For testing only.
        def self.create_from_element(this_shipping, element)
          result = CarrierCalculatedShippingOption.new(this_shipping)
          result.shipping_company = element.elements['shipping-company'].text
          price = (element.elements['price'].text.to_f * 100).to_i
          price_currency = element.elements['price'].attributes['currency']
          result.price = Money.new(price, price_currency)
          result.shipping_type = element.elements['shipping-type']
          result.carrier_pickup = element.elements['carrier-pickup'] rescue nil
          result.additional_fixed_charge = 
              element.elements['additional-fixed-charge'] rescue nil
          result.additional_variable_charge_percent =
              element.elements['additional-variable-charge-percent'] rescue nil
        end
      end
      
      class ShippingPackage
        # Constants for delivery address category
        RESIDENTIAL = 'RESIDENTIAL'
        COMMERCIAL = 'COMMERCIAL'
        
        # The CarrierCalculatedShipping instance that this package belongs to.
        attr_reader :carrier_calculated_shipping
       
        # This contains information about the location from which an order
        # will be shipped. (AnonymousAddress)
        attr_accessor :ship_from
        
        # This indicates whether the shipping method should be applied to
        # a residential or a commercial address. Valid values for this tag
        # are RESIDENTIAL and COMMERCIAL. (String, optional)
        attr_accessor :delivery_address_category
        
        # This contains information about the height of the package being
        # shipped to the customer. (Google::Checktou::Dimension, optional)
        attr_accessor :height
        
        # This contains information about the length of the package being
        # shipped to the customer. (Google::Checktou::Dimension, optional)
        attr_accessor :length
        
        # This contains information about the width of the package being
        # shipped to the customer. (Google::Checktou::Dimension, optional)
        attr_accessor :width
        
        def initialize(carrier_calculated_shipping)
          @carrier_calculated_shipping = carrier_calculated_shipping
        end
        
        # Creates a new ShippingPackage from the given REXML::Element instance.
        # For testing only.
        def self.create_from_element(this_shipping, element)
          result = ShippingPackage.new(this_shipping)
          result.ship_from = ShipFromAddress.create_from_element(element.elements['ship-from'])
          result.delivery_address_category = element.elements['delivery-address-category'].text rescue nil
          result.height = element.elements['height'].text rescue nil
          result.length = element.elements['length'].text rescue nil
          result.width = element.elements['width'].text rescue nil
          return result
        end
      end
    end
    
    # This is a base class for defining the unit of weight and dimension
    class Unit
      # This specifies the unit of measurement that corresponds to a shipping
      # package's length, width or height. The only valid value for 
      # this attribute is IN.
      attr_accessor :unit
      
      # This specifies the numeric value of a unit of measurement 
      # corresponding to an item or a shipping package. (float)
      attr_accessor :value
      
      def initialize
        raise "Google::Checkout::Unit is an abstract class!"
      end
      
      # Creates a new Unit from the given REXML::Element instance.
      def self.create_from_element(element)
        result = self.new(element.attributes['value'].to_f) 
        return result
      end
    end
    
    # This defines package dimension
    class Dimension < Unit
      
      # Constants for unit
      INCH = 'IN'
      
      def initialize(value, unit=INCH)
        @unit = unit
        @value = value.to_f
      end
    end
    
    # This defines item weight
    class Weight < Unit
      # Constants for unit
      LB = 'LB'
      
      def initialize(value, unit=LB)
        @unit = unit
        @value = value.to_f
      end
    end
    
    # This address is used in merchant calculation callback
    class AnonymousAddress
      
      # The address ID (String)
      attr_accessor :address_id
      
      # The buyer's city name (String).
      attr_accessor :city
      
      # The buyers postal/zip code (String).
      attr_accessor :postal_code
      
      # The buyer's geographical region (String).
      attr_accessor :region
      
      # The buyer's country code (String, 2 chars, ISO 3166).
      attr_accessor :country_code
      
      # Creates a new AnonymousAddress from the given REXML::Element instance.
      def self.create_from_element(element)
        result = AnonymousAddress.new
        
        result.address_id = element.attributes['id']
        result.city = element.elements['city'].text
        result.country_code = element.elements['country-code'].text
        result.postal_code = element.elements['postal-code'].text
        result.region = element.elements['region'].text
        return result
      end
    end

    # Address instances are used in NewOrderNotification objects for the buyer's billing
    # and buyer's shipping address.
    class Address < AnonymousAddress
      # Contact name (String, optional).
      attr_accessor :contact_name
      
      # Second Address line (String).
      attr_accessor :address1

      # Second Address line (String optional).
      attr_accessor :address2
      
      # The buyer's city name (String).
      # attr_accessor :city
      # Now inherit from AnonymousAddress
      
      # The buyer's company name (String; optional).
      attr_accessor :company_name
      
      # The buyer's country code (String, 2 chars, ISO 3166).
      # attr_accessor :country_code
      # Now inherit from AnonymousAddress
      
      # The buyer's email address (String; optional).
      attr_accessor :email
      
      # The buyer's phone number (String; optional).
      attr_accessor :fax
      
      # The buyer's phone number (String; Optional, can be enforced in CheckoutCommand).)
      attr_accessor :phone
      
      # The buyers postal/zip code (String).
      # attr_accessor :postal_code
      # Now inherit from AnonymousAddress
      
      
      # The buyer's geographical region (String).
      # attr_accessor :region
      # Now inherit from AnonymousAddress
      
      # Creates a new Address from the given REXML::Element instance.
      def self.create_from_element(element)
        result = Address.new
        
        result.address1 = element.elements['address1'].text
        result.address2 = element.elements['address2'].text rescue nil
        result.city = element.elements['city'].text
        result.company_name = element.elements['company-name'].text rescue nil
        result.contact_name = element.elements['contact-name'].text rescue nil
        result.country_code = element.elements['country-code'].text
        result.email = element.elements['email'].text rescue nil
        result.fax = element.elements['fax'].text rescue nil
        result.phone = element.elements['phone'].text rescue nil
        result.postal_code = element.elements['postal-code'].text
        result.region = element.elements['region'].text
        
        return result
      end
    end
    
    # ItemInfo instances are used in Line-item shipping commands
    class ItemInfo
      # The merchant item id (String)
      attr_reader :merchant_item_id
      
      # An array of tracking data for this item
      attr_reader :tracking_data_arr
      
      def initialize(merchant_item_id)
        @merchant_item_id = merchant_item_id
        @tracking_data_arr = Array.new
      end
      
      def create_tracking_data(carrier, tracking_number)
        tracking_data = TrackingData.new(carrier, tracking_number)
        @tracking_data_arr << tracking_data    
        return tracking_data
      end
    end
    
    # TrackingData instances are used in Line-item shipping commands
    class TrackingData
      # The name of the company responsible for shipping the item. Valid values
      # for this tag are DHL, FedEx, UPS, USPS and Other.
      attr_reader :carrier
      
      # The shipper's tracking number that is associated with an order
      attr_reader :tracking_number
      
      def initialize(carrier, tracking_number)
        @carrier = carrier.to_s
        @tracking_number = tracking_number.to_s
      end
    end
  end
end
