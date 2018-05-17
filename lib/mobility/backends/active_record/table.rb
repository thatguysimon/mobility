# frozen-string-literal: true
require "mobility/backends/active_record"
require "mobility/backends/table"
require "mobility/active_record/model_translation"

module Mobility
  module Backends
=begin

Implements the {Mobility::Backends::Table} backend for ActiveRecord models.

To generate a translation table for a model +Post+, you can use the included
+mobility:translations+ generator:

  rails generate mobility:translations post title:string content:text

This will create a migration which can be run to create the translation table.
If the translation table already exists, it will create a migration adding
columns to that table.

@example Model with table backend
  class Post < ActiveRecord::Base
    extend Mobility
    translates :title, backend: :table
  end

  post = Post.create(title: "foo")
  #<Post:0x00... id: 1>

  post.title
  #=> "foo"

  post.translations
  #=> [#<Post::Translation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  title: "foo">]

  Post::Translation.first
  #=> #<Post::Translation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  title: "foo">

@example Model with multiple translation tables
  class Post < ActiveRecord::Base
    extend Mobility
    translates :title,   backend: :table, table_name: :post_title_translations,   association_name: :title_translations
    translates :content, backend: :table, table_name: :post_content_translations, association_name: :content_translations
  end

  post = Post.create(title: "foo", content: "bar")
  #<Post:0x00... id: 1>

  post.title
  #=> "foo"

  post.content
  #=> "bar"

  post.title_translations
  #=> [#<Post::TitleTranslation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  title: "foo">]

  post.content_translations
  #=> [#<Post::ContentTranslation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  content: "bar">]

  Post::TitleTranslation.first
  #=> #<Post::TitleTranslation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  title: "foo">

  Post::ContentTranslation.first
  #=> #<Post::ContentTranslation:0x00...
  #  id: 1,
  #  locale: "en",
  #  post_id: 1,
  #  title: "bar">
=end
    class ActiveRecord::Table
      include ActiveRecord
      include Table

      class << self
        # @!group Backend Configuration
        # @option options [Symbol] association_name (:translations)
        #   Name of association method
        # @option options [Symbol] table_name Name of translation table
        # @option options [Symbol] foreign_key Name of foreign key
        # @option options [Symbol] subclass_name (:Translation) Name of subclass
        #   to append to model class to generate translation class
        def configure(options)
          table_name = options[:model_class].table_name
          options[:table_name]  ||= "#{table_name.singularize}_translations"
          options[:foreign_key] ||= table_name.downcase.singularize.camelize.foreign_key
          if (association_name = options[:association_name]).present?
            options[:subclass_name] ||= association_name.to_s.singularize.camelize.freeze
          else
            options[:association_name] = :translations
            options[:subclass_name] ||= :Translation
          end
          %i[foreign_key association_name subclass_name table_name].each { |key| options[key] = options[key].to_sym }
        end
        # @!endgroup

        # @param [String] attr Attribute name
        # @param [Symbol] _locale Locale
        # @return [Arel::Attributes::Attribute] Arel node for column on translation table
        def build_node(attr, locale)
          # Arel::Attribute.new(self, attr, locale)
          Arel::Attribute.new(model_class.const_get(subclass_name).arel_table, attr, self)
        end

        private

        def visitor
          @visitor ||= Visitor.new(self)
        end
      end

      class Visitor < Arel::Visitor
        OUTER = ::Arel::Nodes::OuterJoin
        INNER = ::Arel::Nodes::InnerJoin

        def accept(object, relation, locale, invert: false)
          if join_type = super(object, nil, locale, invert: invert)
            join_translations(relation, locale, join_type)
          else
            relation
          end
        end

        private

        %w[model_class subclass_name foreign_key table_name].each do |meth|
          delegate meth, to: :backend_class
        end

        def visit_Arel_Nodes_Equality(object, join_type, locale, invert:)
          if visit_Arel_Nodes_Binary(object, join_type, locale, invert: invert)
            (!invert && [object.left, object.right].any?(&:nil?)) ? OUTER : INNER
          end
        end

        def visit_Array(objects, relation, *args)
          objects.inject(relation) do |rel, obj|
            visit(obj, rel, *args).tap { |j| return j if j == INNER }
          end
        end

        def visit_Arel_Nodes_And(object, relation, *args)
          visit_Array(object.children, relation, *args)
        end

        def visit_Mobility_Arel_Attribute(object, join_type, _locale, **)
          backend_class == object.backend_class ? OUTER : join_type
        end

        def join_translations(relation, locale, join_type)
          return relation if already_joined?(relation, join_type)
          t = model_class.const_get(subclass_name).arel_table
          m = model_class.arel_table
          relation.joins(m.join(t, join_type).
                         on(t[foreign_key].eq(m[:id]).
                            and(t[:locale].eq(locale))).join_sources)
        end

        def already_joined?(relation, join_type)
          if join = get_join(relation)
            return true if (join_type == OUTER) || (INNER === join)
            relation.joins_values = relation.joins_values - [join]
          end
          false
        end

        def get_join(relation)
          relation.joins_values.find { |v| (::Arel::Nodes::Join === v) && (v.left.name == table_name.to_s) }
        end
      end
      private_constant :Visitor

      setup do |_attributes, options|
        association_name = options[:association_name]
        subclass_name    = options[:subclass_name]

        translation_class =
          if self.const_defined?(subclass_name, false)
            const_get(subclass_name, false)
          else
            const_set(subclass_name, Class.new(Mobility::ActiveRecord::ModelTranslation))
          end

        translation_class.table_name = options[:table_name]

        has_many association_name,
          class_name:  translation_class.name,
          foreign_key: options[:foreign_key],
          dependent:   :destroy,
          autosave:    true,
          inverse_of:  :translated_model,
          extend:      TranslationsHasManyExtension

        translation_class.belongs_to :translated_model,
          class_name:  name,
          foreign_key: options[:foreign_key],
          inverse_of:  association_name,
          touch: true

        before_save do
          required_attributes = self.class.translated_attribute_names & translation_class.attribute_names
          send(association_name).destroy_empty_translations(required_attributes)
        end

        module_name = "MobilityArTable#{association_name.to_s.camelcase}"
        unless const_defined?(module_name)
          dupable = Module.new do
            define_method :initialize_dup do |source|
              super(source)
              self.send("#{association_name}=", source.send(association_name).map(&:dup))
            end
          end
          include const_set(module_name, dupable)
        end
      end

      # Returns translation for a given locale, or builds one if none is present.
      # @param [Symbol] locale
      def translation_for(locale, _)
        translation = translations.in_locale(locale)
        translation ||= translations.build(locale: locale)
        translation
      end

      module TranslationsHasManyExtension
        # Returns translation in a given locale, or nil if none exist
        # @param [Symbol, String] locale
        def in_locale(locale)
          locale = locale.to_s
          find { |t| t.locale == locale }
        end

        # Destroys translations with all empty values
        def destroy_empty_translations(required_attributes)
          each { |t| destroy(t) if required_attributes.map(&t.method(:send)).none? }
        end
      end
    end
  end
end
