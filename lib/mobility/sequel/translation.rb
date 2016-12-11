module Mobility
  module Sequel
    class Translation < ::Sequel::Model(:mobility_translations)
      plugin :polymorphic
      plugin :validation_helpers
      many_to_one :translatable, polymorphic: true

      def validate
        super
        validates_presence [:locale, :key, :translatable_id, :translatable_type]
        validates_unique   [:locale, :key, :translatable_id, :translatable_type]
      end

      def __mobility_get
        value
      end

      def __mobility_set(value)
        self.value = value
      end
    end
  end
end
