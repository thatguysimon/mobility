# frozen-string-literal: true
require "mobility/arel/visitor"

module Mobility
  module Arel
    module Visitors
      class TableVisitor < Arel::Visitor
        DEFAULT_JOIN = INNER_JOIN

        private

        def visit_collection(objects)
          combine_visit(objects, DEFAULT_JOIN)
        end

        def visit_Arel_Nodes_Equality(object)
          nils, nodes = [object.left, object.right].partition(&:nil?)
          if nodes.any?(&method(:visit))
            nils.empty? ? INNER_JOIN : OUTER_JOIN
          end
        end

        def visit_Array(objects)
          combine_visit(objects, INNER_JOIN)
        end

        def visit_Arel_Nodes_Or(object)
          combine_visit([object.left, object.right], OUTER_JOIN)
        end

        def visit_Mobility_Arel_Attribute(object)
          (backend_class == object.backend_class) && DEFAULT_JOIN
        end

        def combine_visit(objects, join_type)
          objects.map { |obj|
            visited = visit(obj)
            return visited if visited == join_type
            visited
          }.compact.first
        end
      end
    end
  end
end
