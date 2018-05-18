# frozen-string-literal: true
require "mobility/arel/visitor"

module Mobility
  module Arel
    module Visitors
      class KeyValueVisitor < Arel::Visitor
        private

        def visit_collection(objects)
          objects.map(&method(:visit)).compact.inject(&:merge)
        end

        def visit_Arel_Nodes_Equality(object)
          nils, nodes = [object.left, object.right].partition(&:nil?)
          hash = visit_collection(nodes)
          hash = hash.transform_values { OUTER_JOIN } if nils.present?
          hash
        end

        def visit_Array(objects)
          combine_visit(objects, INNER_JOIN)
        end

        def visit_Arel_Nodes_Or(object)
          combine_visit([object.left, object.right], OUTER_JOIN)
        end

        def visit_Mobility_Arel_Attribute(object)
          if object.backend_class == backend_class
            { object.attribute_name => INNER_JOIN }
          end
        end

        def combine_visit(objects, join_type)
          objects.map(&method(:visit)).compact.inject do |hash, visited|
            visited.merge(hash) { |_, old, new| old == join_type ? old : new }
          end
        end
      end
    end
  end
end
