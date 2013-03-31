# -*- coding: utf-8 -*-
require 'gmail'
require 'yaml'
require 'kconv'
require 'date'

class Gmikul

    #コンストラクタ
    def initialize(addr,pass)
        @gmail = Gmail.new(addr,pass)
        @mail = Array.new
        @id = -10000
    end

    #未読メールはおるか？
    def haveUnread(lasttime)
        begin
            mail_count = @gmail.inbox.count(:unread, :after => lasttime)
        rescue
            mail_count = mail_count_latest = -1
        else
        #おるでｗ/おらんでｗ
        return mail_count
        end
    end

    #既に取得したものかどうかを返す
    #取得済み => true 未取得 => false
    def isAlreadyGet(message_id)
        res = false
        @mail.each do |h|
            res |= h.value?(message_id)
        end
        return res
    end

    #メールをの差出人を返す
    def getFrom(mes)
        begin
            s_from = mes.from[0]
            from = s_from.name == nil ? "#{s_from.mailbox}#{s_from.host}" : s_from.name
        rescue
            from = nil
        end
        return from
    end

    #メールの件名を返す
    def getSub(mes)
        begin
            subject = mes.subject.toutf8
        rescue
            subject = nil
        end
        return subject
    end

    #メールの本文を返す
    def getBody(mes)
        begin
            body = mes.text_part.decoded
        rescue
            body = nil
        end
        return body
    end

    # Messageの配列を返す
    def genMessage(lasttime,incbody)
        @gmail.inbox.emails(:unread, :after => lasttime).map do |mes|
            #既に取得済みなら次へ
            next if isAlreadyGet(mes.message_id)
            #文章を生成
            text = String.new
            text << (self.getFrom(mes) == nil ? '' : "#{self.getFrom(mes)}さんから")
            text << (self.getSub(mes) == nil ? '' : "「#{self.getSub(mes)}」という件名の")
            text << "メールが届いていますよ。"
            #本文の表示が有効の場合
            if incbody
                text << (self.getBody(mes) == nil ? "\n **本文を表示できません**" : "\n[本文]\n#{self.getBody(mes)}")
            end
            mes.mark(:unread)
            n_mail = Message.new(:message => text, :system => true)
            n_mail[:user] = User.new(
                                :id     => @id,
                                :idname => "Gmikul",
                                :name   => "mikuttter_Gmikul" ,
                                :profile_image_url => MUI::Skin.get("icon.png"))
            @mail << {post: n_mail, id: mes.message_id} 
            @id -= 1              
        end
    
        mesary = Array.new
        @mail.each do |h|
            mesary << h[:post]
        end
        return mesary
    end

    #ログアウト    
    def logout
    @gmail.primary.logout
    end
end


Plugin.create(:mikutter_gmikul) do
    #設定
    settings("Gmikul") do
        adjustment("更新間隔[sec]" , :gmikul_interval, 10, 3000)
        adjustment("未読を取得する日数" , :gmikul_days, 1, 30)
        boolean("通知タブに本文を表示する",:gmikul_body)
    end

    #タブを作成
    tab :mikutter_gmikul, "Gmikul" do
        set_icon File.expand_path(File.join(File.dirname(__FILE__), 'gmail.png'))
        timeline :mailbox
    end

    #みくったーちゃん
    def announce(text)
        Plugin.call(:update, nil, [Message.new(:message => text, :system => true)])
    end
 
    #投稿ボックスをくりあ
    def clearBox(buf)
        buf.text = ''
        Plugin.filter_cancel!
    end
    
    #専用タブに流す
    def pushMailbox(mail)
        timeline(:mailbox).clear
        mail.each do |m|
            timeline(:mailbox) << m
        end
    end

    #投稿ボックスの中身を判定して処理
    def gmikulInBox(buf)
        if buf.text =~ /^@gmikul/ then
            count = $gmikul.haveUnread($lasttime)
            announce(maketext(count))
            mail = $gmikul.genMessage($lasttime,UserConfig[:gmikul_body])
            pushMailbox(mail)
            clearBox(buf)
        end
    end

    #テキストを生成
    def maketext(count)
        return "未読メールの取得に失敗しました。" if(count < 0)
        return count == 0 ? "未読メールはありません。" : "#{count}件の未読メールがあります。"
    end
 
    #起動時
    on_boot do 
        UserConfig[:gmikul_interval] ||= 180
        UserConfig[:gmikul_days] ||= 1 
        begin  
            config = YAML.load_file(File.join(File.dirname(__FILE__),"config.yaml"))
            $gmikul = Gmikul.new(config["gmail"]["addr"],config["gmail"]["pass"])
            $lasttime = DateTime.now  - UserConfig[:gmikul_days].to_i
            count = $gmikul.haveUnread($lasttime)
            announce(maketext(count))
            mail = $gmikul.genMessage($lasttime,UserConfig[:gmikul_body])
            pushMailbox(mail)
        rescue
            announce("アカウント情報が間違っているのかもー＞＜")
        end
    end 

    #更新時間を設定
    def setTimer
        return UserConfig[:gmikul_interval].to_i
    end

    #未読メールを設定した間隔で取得
    def autoUpdate
        Reserver.new(setTimer){
            count = $gmikul.haveUnread($lasttime)
            mail = $gmikul.genMessage($lasttime,UserConfig[:gmikul_body]) 
            unless mail.empty? then
                announce(maketext(count))
                pushMailbox(mail)
            else
                timeline(:mailbox).clear
            end
            sleep 1
            autoUpdate
        }
    end
    
    #投稿ボックス、ゲットだぜ！
    def getPostbox
        filter_gui_postbox_post do |postbox|
            buf = ObjectSpace.each_object(Gtk::PostBox).to_a.first.widget_post.buffer
            gmikulInBox(buf)
            [postbox]
        end
    end
    
    getPostbox
    autoUpdate
    
    at_exit{$gmikul.logout}
end
