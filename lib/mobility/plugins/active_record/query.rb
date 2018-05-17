# frozen-string-literal: true
module Mobility
  module Plugins
=begin

Adds a scope which enables querying on translated attributes using +where+ and
+not+ as if they were normal attributes. Under the hood, this plugin uses the
generic +build_node+ and +add_translations+ methods implemented in each backend
class to build ActiveRecord queries from Arel nodes.

=end
    module ActiveRecord
      module Query
        class << self
          def apply(attributes)
            model_class = attributes.model_class

            unless const_defined?(:QueryMethod)
              const_set :QueryMethod, Module.new
              QueryMethod.module_eval <<-EOM, __FILE__, __LINE__ + 1
                def #{Mobility.query_method}(*attrs, locale: Mobility.locale)
                  if attrs.empty?
                    all.extending(QueryExtension)
                  else
                    backends = attrs.map { |attr| mobility.backends[attr.to_sym] }.uniq
                    nodes    = attrs.map { |attr| mobility[attr] }
                    predicate = yield(nodes)
                    processed = backends.uniq.inject(all) { |relation, klass|
                      klass.accept(predicate, relation, locale)
                    }.where(predicate)
                  end
                end
              EOM
              private_constant :QueryMethod
            end

            model_class.extend QueryMethod
            model_class.extend FindByMethods.new(*attributes.names)
          end
        end

        module QueryExtension
          def where!(opts, *rest)
            QueryBuilder.build(self, opts) do |untranslated_opts|
              untranslated_opts ? super(untranslated_opts, *rest) : super
            end
          end

          def where(opts = :chain, *rest)
            opts == :chain ? WhereChain.new(spawn) : super
          end

          class WhereChain < ::ActiveRecord::QueryMethods::WhereChain
            def not(opts, *rest)
              QueryBuilder.build(@scope, opts, invert: true) do |untranslated_opts|
                untranslated_opts ? super(untranslated_opts, *rest) : super
              end
            end
          end

          module QueryBuilder
            class << self
              def build(scope, where_opts, invert: false)
                return yield unless Hash === where_opts

                locale = Mobility.locale
                opts = where_opts.with_indifferent_access

                maps = build_maps!(scope.mobility, opts, locale, invert: invert)
                return yield if maps.empty?

                base = opts.empty? ? scope : yield(opts)
                maps.inject(base) { |rel, map| map[rel] }
              end

              private

              def build_maps!(interface, opts, locale, invert:)
                keys = opts.keys.map(&:to_s)
                mods = interface.modules.select { |mod| mod.options[:query] }

                mods.map { |mod|
                  next if (i18n_keys = mod.names & keys).empty?

                  predicates = i18n_keys.map do |key|
                    build_predicate(interface[key.to_sym, locale], opts.delete(key))
                  end

                  ->(relation) do
                    relation = mod.backend_class.accept(predicates, relation, locale, invert: invert)
                    predicates = predicates.map(&method(:invert_predicate)) if invert
                    relation.where(predicates.inject(&:and))
                  end
                }.compact
              end

              def build_predicate(node, values)
                nils, vals = partition_values(values)

                return node.eq(nil) if vals.empty?

                predicate = vals.length == 1 ? node.eq(vals.first) : node.in(vals)
                predicate = predicate.or(node.eq(nil)) unless nils.empty?
                predicate
              end

              def partition_values(values)
                Array.wrap(values).uniq.partition(&:nil?)
              end

              # Adapted from AR::Relation::WhereClause#invert_predicate
              def invert_predicate(node)
                case node
                when ::Arel::Nodes::In
                  ::Arel::Nodes::NotIn.new(node.left, node.right)
                when ::Arel::Nodes::Equality
                  ::Arel::Nodes::NotEqual.new(node.left, node.right)
                else
                  ::Arel::Nodes::Not.new(node)
                end
              end
            end
          end

          private_constant :WhereChain, :QueryBuilder
        end

        class FindByMethods < Module
          def initialize(*attributes)
            attributes.each do |attribute|
              module_eval <<-EOM, __FILE__, __LINE__ + 1
              def find_by_#{attribute}(value)
                find_by(#{attribute}: value)
              end
              EOM
            end
          end
        end

        private_constant :QueryExtension, :FindByMethods
      end
    end
  end
end
