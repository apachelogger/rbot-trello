require 'trello'
require 'pp'

class TrelloPlugin < Plugin
  def initialize
    super

    # Remove the timestamp on startup to prevent polls of events while we were
    # offline and a resulting flood of events.
    @registry.delete(:last_check)
    @registry.flush

    Config.register Config::ArrayValue.new('trello.token',
                                           :default => '',
                                           :wizard => false,
                                           :desc => "kittens")

    @timer = @bot.timer.add(50) do
      Trello.configure do |config|
        config.developer_public_key = '4592c3158846aa90d063fc5a6779a4c8'
        config.member_token = @bot.config['trello.token']
      end

      k = Trello::Organization.find('kubuntu')
      b = []
      k.boards.each do |board|
        b << board unless board.closed
      end

      unless @registry.key?(:last_check)
        puts("trello : registry had no last_check value, skipping this run")
        b = []
      end
      since  = @registry[:last_check]
      before = Time.now.utc.to_s
      @registry[:last_check] = before
      puts("trello : since: #{since} -> before: #{before} || boards: #{b.size}")

      b.each do |board|
        board.actions({:filter => 'createCard,updateCard,commentCard',
                       :since => since,
                       :before => before}).each do |action|
            case action.type
            when 'createCard'
              card_create(action)
            when 'updateCard'
              card_update(action)
            when 'commentCard'
              card_comment(action)
            when 'removeMemberFromCard', 'addMemberToCard', 'moveCardFromBoard',
                 'updateBoard', 'createBoard', 'addToOrganizationBoard',
                 'addChecklistToCard', 'updateChecklist', 'addMemberToBoard',
                 'makeAdminOfBoard', 'moveCardToBoard', 'createList',
                 'updateCheckItemStateOnCard', 'updateList', 'moveListToBoard',
                 'copyCommentCard', 'copyCard'
              # skip
            else
              unhandle(action)
            end
          end
        end
        #             rescue Exception => e
        #                 error "Error watching #{feed}: #{e.inspect}"
        #                 debug e.backtrace.join("\n")
        #                 failures += 1
      end
    end

    def cleanup
      @bot.timer.remove(@timer)
      super
    end

    private
    def announce(string)
      @bot.__send__(:notice, '#kubuntu-devel', string, :overlong => :truncate)
    end

    def unhandle(action)
      announce "unhandled action"
      pp action
    end

    def card_create(action)
      announce "[#{action.board.name}] New card '#{action.card.name}' created #{action.card.url}"

    end

    def card_update_list(action, old)
      card = action.card
      originList = Trello::List.find(old['idList'])
      targetList = card.list
      if card.nil? or originList.nil? or targetList.nil?
        unhandle(action)
        raise RandomError
      end
      announce "[#{action.board.name}] Card '#{card.name}' moved from #{originList.name} to #{targetList.name} #{action.card.url}"
    end

    def card_update_name(action, old)
      card = action.card
      announce "[#{action.board.name}] Card '#{old['name']}' renamed to '#{card.name}' #{action.card.url}"
    end

    def card_update(action)
      if action.data.key?('old')
        old = action.data['old']
        begin
          card_update_list(action, old) if old.key?('idList')
          card_update_name(action, old) if old.key?('name')
          return
        rescue Exception => e # bypass the return
          p e
        end
      end
      unhandle(action)
    end

    def card_comment(action)
      #     puts "[#{action.board.name}] #{action.member_creator.full_name} commented on '#{action.card.name}' :: #{action.data['text']} // #{action.card.url}"
      announce "[#{action.board.name}] #{action.member_creator.full_name} commented on '#{action.card.name}' #{action.card.url}"
    end
  end

  plugin = TrelloPlugin.new
  plugin.register('trello')
