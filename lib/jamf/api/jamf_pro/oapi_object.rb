# Copyright 2020 Pixar
#
#    Licensed under the Apache License, Version 2.0 (the "Apache License")
#    with the following modification; you may not use this file except in
#    compliance with the Apache License and the following modification to it:
#    Section 6. Trademarks. is deleted and replaced with:
#
#    6. Trademarks. This License does not grant permission to use the trade
#       names, trademarks, service marks, or product names of the Licensor
#       and its affiliates, except as required to comply with Section 4(c) of
#       the License and to reproduce the content of the NOTICE file.
#
#    You may obtain a copy of the Apache License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the Apache License with the above modification is
#    distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#    KIND, either express or implied. See the Apache License for the specific
#    language governing permissions and limitations under the Apache License.
#
#

# The module
module Jamf

  # Classes
  #####################################

  class OAPIObject

    extend Jamf::BaseClass

    # Constants
    #####################################

    # Public Class Methods
    #####################################

    # By default,OAPIObjects (as a whole) are mutable,
    # although some attributes may not be (see OAPI_PROPERTIES in the JSONObject
    # docs)
    #
    # When an entire sublcass of OAPIObject is read-only/immutable,
    # `extend Jamf::Immutable`, which will override this to return false.
    # Doing so will prevent any setters from being created for the subclass
    # and will cause Jamf::Resource.save to raise an error
    #
    def self.mutable?
      true
    end

    # An array of attribute names that are required when
    # making new instances
    # See the OAPI_PROPERTIES documentation in {Jamf::JSONObject}
    def self.required_attributes
      self::OAPI_PROPERTIES.select { |_attr, deets| deets[:required] }.keys
    end

    # create getters and setters for subclasses of APIObject
    # based on their OAPI_PROPERTIES Hash.
    #
    # This method can't be private, cuz we want to call it from a
    # Zeitwerk callback when subclasses are loaded.
    ##############################
    def self.parse_oapi_properties
      return if @oapi_properties_parsed

      got_primary = false

      # move this to Jamf::CollectionResource, define them as needed
      # probably with method_missing?
      # need_list_methods = ancestors.include?(Jamf::CollectionResource)

      self::OAPI_PROPERTIES.each do |attr_name, attr_def|

        # see above comment
        # don't make one for :id, that one's hard-coded into CollectionResource
        # create_list_methods(attr_name, attr_def) if need_list_methods && attr_def[:identifier] && attr_name != :id

        # there can be only one (primary ident)
        if attr_def[:identifier] == :primary
          raise Jamf::UnsupportedError, 'Two identifiers marked as :primary' if got_primary

          got_primary = true
        end

        # create getter unless the attr is write only
        create_getters attr_name, attr_def unless attr_def[:writeonly]

        # Don't crete setters for readonly attrs, or immutable objects
        next if attr_def[:readonly] || !mutable?

        create_setters attr_name, attr_def
      end #  do |attr_name, attr_def|

      @oapi_properties_parsed = true
    end # parse_object_model

    # Private Class Methods
    #####################################

    # Initialize a multi-values attribute as an empty array
    # if it hasn't been created yet
    def self.initialize_multi_value_attr_array(attr_name)
      return if instance_variable_get("@#{attr_name}").is_a? Array

      instance_variable_set("@#{attr_name}", [])
    end
    private_class_method :initialize_multi_value_attr_array

    # create a getter for an attribute, and any aliases needed
    ##############################
    def self.create_getters(attr_name, attr_def)
      # multi_value - only return a frozen dup, no direct editing of the Array
      if attr_def[:multi]
        define_method(attr_name) do
          initialize_multi_value_attr_array attr_name

          instance_variable_get("@#{attr_name}").dup.freeze
        end

      # single value
      else
        define_method(attr_name) { instance_variable_get("@#{attr_name}") }
      end

      # all booleans get predicate ? aliases
      alias_method("#{attr_name}?", attr_name) if attr_def[:class] == :boolean
    end # create getters
    private_class_method :create_getters

    # create setter(s) for an attribute, and any aliases needed
    ##############################
    def self.create_setters(attr_name, attr_def)
      # multi_value
      if attr_def[:multi]
        create_array_setters(attr_name, attr_def)
        return
      end

      # single value
      define_method("#{attr_name}=") do |new_value|
        new_value = validate_attr attr_name, new_value
        old_value = instance_variable_get("@#{attr_name}")
        return if new_value == old_value

        instance_variable_set("@#{attr_name}", new_value)
        note_unsaved_change attr_name, old_value
      end # define method
    end # create_setters
    private_class_method :create_setters

    ##############################
    def self.create_array_setters(attr_name, attr_def)
      create_full_array_setters(attr_name, attr_def)
      create_append_setters(attr_name, attr_def)
      create_prepend_setters(attr_name, attr_def)
      create_insert_setters(attr_name, attr_def)
      create_delete_at_setters(attr_name, attr_def)
      create_delete_if_setters(attr_name, attr_def)
    end # def create_multi_setters
    private_class_method :create_array_setters

    # The  attr=(newval) setter method for array values
    ##############################
    def self.create_full_array_setters(attr_name, attr_def)
      define_method("#{attr_name}=") do |new_value|
        initialize_multi_value_attr_array attr_name

        raise Jamf::InvalidDataError, 'Value must be an Array' unless new_value.is_a? Array

        # validate each item of the new array
        new_value.map! { |item| validate_attr attr_name, item }
        old_value = instance_variable_get("@#{attr_name}")
        return if new_value == old_value

        instance_variable_set("@#{attr_name}", new_value)
        note_unsaved_change attr_name, old_value
      end # define method

      return unless attr_def[:aliases]
    end # create_full_array_setter
    private_class_method :create_full_array_setters

    # The  attr_append(newval) setter method for array values
    ##############################
    def self.create_append_setters(attr_name, attr_def)
      define_method("#{attr_name}_append") do |new_value|
        initialize_multi_value_attr_array attr_name

        new_value = validate_attr attr_name, new_value
        old_array = instance_variable_get("@#{attr_name}").dup

        instance_variable_get("@#{attr_name}") << new_value
        note_unsaved_change attr_name, old_array
      end # define method

      # always have a << alias
      alias_method "#{attr_name}<<", "#{attr_name}_append"
    end # create_append_setters
    private_class_method :create_append_setters

    # The  attr_prepend(newval) setter method for array values
    ##############################
    def self.create_prepend_setters(attr_name, attr_def)
      define_method("#{attr_name}_prepend") do |new_value|
        initialize_multi_value_attr_array attr_name

        new_value = validate_attr attr_name, new_value
        old_array = instance_variable_get("@#{attr_name}").dup
        instance_variable_get("@#{attr_name}").unshift new_value
        note_unsaved_change attr_name, old_array
      end # define method
    end # create_prepend_setters
    private_class_method :create_prepend_setters

    # The  attr_insert(index, newval) setter method for array values
    def self.create_insert_setters(attr_name, attr_def)
      define_method("#{attr_name}_insert") do |index, new_value|
        initialize_multi_value_attr_array attr_name

        new_value = validate_attr attr_name, new_value
        old_array = instance_variable_get("@#{attr_name}").dup
        instance_variable_get("@#{attr_name}").insert index, new_value
        note_unsaved_change attr_name, old_array
      end # define method
    end # create_insert_setters
    private_class_method :create_insert_setters

    # The  attr_delete_at(index) setter method for array values
    ##############################
    def self.create_delete_at_setters(attr_name, attr_def)
      define_method("#{attr_name}_delete_at") do |index|
        initialize_multi_value_attr_array attr_name

        old_array = instance_variable_get("@#{attr_name}").dup
        deleted = instance_variable_get("@#{attr_name}").delete_at index
        note_unsaved_change attr_name, old_array if deleted
      end # define method
    end # create_insert_setters
    private_class_method :create_delete_at_setters

    # The  attr_delete_if  setter method for array values
    ##############################
    def self.create_delete_if_setters(attr_name, attr_def)
      define_method("#{attr_name}_delete_if") do |&block|
        initialize_multi_value_attr_array attr_name

        old_array = instance_variable_get("@#{attr_name}").dup
        instance_variable_get("@#{attr_name}").delete_if &block
        note_unsaved_change attr_name, old_array if old_array != instance_variable_get("@#{attr_name}")
      end # define method
    end # create_insert_setters
    private_class_method :create_delete_if_setters

    # Used by auto-generated setters and .create to validate new values.
    #
    # returns a valid value or raises an exception
    #
    # This method only validates single values. When called from multi-value
    # setters, it is used for each value individually.
    #
    # @param attr_name[Symbol], a top-level key from OAPI_PROPERTIES for this class
    #
    # @param value [Object] the value to validate for that attribute.
    #
    # @return [Object] The validated, possibly converted, value.
    #
    def self.validate_attr(attr_name, value)
      attr_def = self::OAPI_PROPERTIES[attr_name]
      raise ArgumentError, "Unknown attribute: #{attr_name} for #{self} objects" unless attr_def

      # validate the value based on the OAPI definition.
      Jamf::Validate.oapi_attr value, attr_def

      # if this is an identifier, it must be unique
      # TODO: move this to colloection resouce code
      # Jamf::Validate.doesnt_exist(value, self, attr_name, cnx: cnx) if attr_def[:identifier] && superclass == Jamf::CollectionResource

    end # validate_attr(attr_name, value)

    # Constructor

    # Make an instance. Data comes from the API
    #
    # @param data[Hash] the data for constructing a new object.
    #
    def initialize(**data)
      # creating a new one, not fetching from the API
      creating = data.delete :creating_from_create
      if creating
        self.class::OAPI_PROPERTIES.keys.each do |attr_name|
          # we'll enforce required values when we save
          next unless data.key? attr_name

          # use our setters for each value so that they are in the unsaved changes
          send "#{attr_name}=", data[attr_name]
        end
        return
      end

      parse_init_data data
    end # init

    # Instance Methods
    #####################################

    # a hash of all unsaved changes, including embedded JSONObjects
    #
    def unsaved_changes
      return {} unless self.class.mutable?

      changes = @unsaved_changes.dup

      self.class::OAPI_PROPERTIES.each do |attr_name, attr_def|
        # skip non-Class attrs
        next unless attr_def[:class].is_a? Class

        # the current value of the thing, e.g. a Location
        # which may have unsaved changes
        value = instance_variable_get "@#{attr_name}"

        # skip those that don't have any changes
        next unless value.respond_to? :unsaved_changes?
        attr_changes = value.unsaved_changes
        next if attr_changes.empty?

        # add the sub-changes to ours
        changes[attr_name] = attr_changes
      end
      changes[:ext_attrs] = ext_attrs_unsaved_changes if self.class.include? Jamf::Extendable
      changes
    end

    # return true if we or any of our attributes have unsaved changes
    #
    def unsaved_changes?
      return false unless self.class.mutable?

      !unsaved_changes.empty?
    end

    def clear_unsaved_changes
      return unless self.class.mutable?

      unsaved_changes.keys.each do |attr_name|
        attrib_val = instance_variable_get "@#{attr_name}"
        if self.class::OAPI_PROPERTIES[attr_name][:multi]
          attrib_val.each { |item| item.send :clear_unsaved_changes if item.respond_to? :clear_unsaved_changes }
        elsif attrib_val.respond_to? :clear_unsaved_changes
          attrib_val.send :clear_unsaved_changes
        end
      end
      ext_attrs_clear_unsaved_changes if self.class.include? Jamf::Extendable
      @unsaved_changes = {}
    end

    # @return [Hash] The data to be sent to the API, as a Hash
    #  to be converted to JSON by the Jamf::Connection
    #
    def to_jamf
      data = {}
      self.class::OAPI_PROPERTIES.each do |attr_name, attr_def|

        raw_value = instance_variable_get "@#{attr_name}"

        # If its a multi-value attribute, process it and  go on
        if attr_def[:multi]
          data[attr_name] = multi_to_jamf(raw_value, attr_def)
          next
        end

        # if its a single-value object, process it and go on.
        cooked_value = single_to_jamf(raw_value, attr_def)
        # next if cooked_value.nil? # ignore nil
        data[attr_name] = cooked_value
      end # unsaved_changes.each
      data
    end

    # Only works for PATCH endpoints.
    #
    # @return [Hash] The changes that need to be sent to the API, as a Hash
    #  to be converted to JSON by the Jamf::Connection
    #
    def to_jamf_changes_only
      return unless self.class.mutable?

      data = {}
      unsaved_changes.each do |attr_name, changes|
        attr_def = self.class::OAPI_PROPERTIES[attr_name]

        # readonly attributes can't be changed
        next if attr_def[:readonly]

        # here's the new value for this attribute
        raw_value = changes[:new]

        # If its a multi-value attribute, process it and  go on
        if attr_def[:multi]
          data[attr_name] = multi_to_jamf(raw_value, attr_def)
          next
        end

        # if its a single-value object, process it and go on.
        cooked_value = single_to_jamf(raw_value, attr_def)
        next if cooked_value.nil? # ignore nil

        data[attr_name] = cooked_value
      end # unsaved_changes.each
      data
    end

    # Print the JSON version of the to_jamf outout
    # mostly for debugging/troubleshooting
    def pretty_jamf_json
      puts JSON.pretty_generate(to_jamf)
    end

    # Remove large cached items from
    # the instance_variables used to create
    # pretty-print (pp) output.
    #
    # @return [Array] the desired instance_variables
    #
    def pretty_print_instance_variables
      vars = super.sort
      vars
    end

    # Private Instance Methods
    #####################################
    private

    def note_unsaved_change(attr_name, old_value)
      return unless self.class.mutable?

      @unsaved_changes ||= {}
      new_val = instance_variable_get "@#{attr_name}"
      if @unsaved_changes[attr_name]
        @unsaved_changes[attr_name][:new] = new_val
      else
        @unsaved_changes[attr_name] = { old: old_value, new: new_val }
      end
    end

    # take data from the API and populate an our instance attributes
    #
    # @param data[Hash] The parsed API JSON data for this instance
    #
    # @return [void]
    #
    def parse_init_data(data)
      self.class::OAPI_PROPERTIES.each do |attr_name, attr_def|
        unless data.key? attr_name
          raise Jamf::InvalidDataError, "Initialization must include the key '#{attr_name}:'" if attr_def[:required]

          next
        end

        value =
          if attr_def[:multi]
            raw_array = data[attr_name] || []
            raw_array.map { |v| parse_single_init_value v, attr_name, attr_def }
          else
            parse_single_init_value data[attr_name], attr_name, attr_def
          end
        instance_variable_set "@#{attr_name}", value
      end # OAPI_PROPERTIES.each
    end # parse_init_data(data)

    # Parse an individual value from the API into an
    # attribute or a member of a multi attribute
    # Description of #parse_single_init_value
    #
    # @param api_value [Object] The parsed JSON value from the API
    # @param attr_name [Symbol] The attribute we're processing
    # @param attr_def [Hash] The attribute definition
    #
    # @return [Object] The storable value.
    #
    def parse_single_init_value(api_value, attr_name, attr_def)
      # we do get nils from the API, and they should stay nil
      return nil if api_value.nil?

      # an enum value
      if attr_def[:enum]
        parse_enum_value(api_value, attr_name, attr_def)

      # a Class value
    elsif attr_def[:class].instance_of? Class
        attr_def[:class].new api_value

      # a :j_id value. See the docs for OAPI_PROPERTIES in Jamf::OAPIObject
      elsif attr_def[:class] == :j_id
        api_value.to_s

      # a JSON value
      else
        api_value
      end # if attr_def[:class].class
    end

    # Parse an api value into an attribute with an enum
    #
    # @param (see parse_single_init_value)
    # @return (see parse_single_init_value)
    #
    def parse_enum_value(api_value, attr_name, attr_def)
      OAPIValidate.in_enum  api_value, enum: attr_def[:enum], msg: "#{api_value} is not in the allowed values for attribute #{attr_name}. Must be one of: #{attr_def[:enum].join ', '}"
    end

    # call to_jamf on a single value
    #
    def single_to_jamf(raw_value, attr_def)
      # if the attrib class is a  Class,
      # call its changes_to_jamf or to_jamf method
      if attr_def[:class].is_a? Class
        data = raw_value.to_jamf
        data.is_a?(Hash) && data.empty? ? nil : data

      # otherwise, use the value as-is
      else
        raw_value
      end
    end

    # Call to_jamf on an array value
    #
    def multi_to_jamf(raw_array, attr_def)
      raw_array ||= []
      raw_array.map { |raw_value| single_to_jamf(raw_value, attr_def) }.compact
    end

    # wrapper for class method
    def validate_attr(attr_name, value)
      self.class.validate_attr attr_name, value
    end

  end # class JSONObject

end # module JAMF
