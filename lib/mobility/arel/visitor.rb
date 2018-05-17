# frozen-string-literal: true
module Mobility
  module Arel
    class Visitor < ::Arel::Visitors::Visitor
      attr_reader :backend_class

      def initialize(backend_class = nil)
        super()
        @backend_class = backend_class
      end

      def accept(object, relation, locale, invert: false)
        visit(object, relation, locale, invert: invert)
      end

      private

      # paraphrased from Arel::Visitors::Visitor#visit
      def visit(object, relation, locale, options)
        dispatch_method = dispatch[object.class]
        send(dispatch_method, object, relation, locale, options)
      rescue NoMethodError => e
        raise e if respond_to?(dispatch_method, true)
        superklass = object.class.ancestors.find { |klass|
          respond_to?(dispatch[klass], true)
        }
        return relation unless superklass
        dispatch[object.class] = dispatch[superklass]
        retry
      end

      def visit_collection(objects, relation, *args)
        objects.inject(relation) { |rel, obj| visit(obj, rel, *args) }
      end
      alias :visit_Array :visit_collection

      def visit_Arel_Nodes_Unary(object, relation, *args)
        visit(object.expr, relation, *args)
      end

      def visit_Arel_Nodes_Binary(object, relation, *args)
        visit_collection([object.left, object.right], relation, *args)
      end

      def visit_Arel_Nodes_Function(object, relation, *args)
        visit_collection(object.expressions, relation, *args)
      end

      def visit_Arel_Nodes_And(object, relation, *args)
        visit_collection(object.children, relation, *args)
      end

      def visit_Arel_Nodes_Case(object, relation, *args)
        visit_collection([object.case, object.conditions, object.default], relation, *args)
      end
    end
  end
end
