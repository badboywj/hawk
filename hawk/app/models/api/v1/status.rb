module Api
  module V1
    class Status < Cib

      attr_accessor :state
      attr_accessor :events

      def initialize(user="hacluster")
        get_cib(user)
        @events = []
        @state = "unknown"
        @state = "offline" if mode == :offline
        @state = "online" if mode == :online
      end

      def version
        if @mode == :online
          CibTools.epoch_string @xml.root
        else
          "0:0:0"
        end
      end

      def mode
        @mode
      end

      def xml
        @xml if @mode == :online
      end

      def root
        {
          version: version,
          cluster: cluster,
          nodes: nodes,
          resources: resources,
        }
      end

      def cluster
        {
          state: @state,
          events: @events
        }
      end

      def nodes
        return [] if @xml.nil?
        @xml.elements.collect("/cib/configuration/nodes/node") do |xml|
          Node.new @xml, xml.attributes['uname'] || xml.attributes['id']
        end
      end

      def resources
        return [] # if @xml.nil?
        # @xml.elements.collect("/cib/configuration//primitive") do |xml|
        #   Resource.new @xml, xml.attributes['id']
        # end
      end

      def error(message)
        @events << {
          message: message,
          type: "error",
          id: []
        }
      end

    end
  end
end
