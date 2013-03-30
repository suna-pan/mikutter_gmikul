# -*- coding: utf-8 -*-
require 'gmail'
require 'yaml'
require 'kconv'
require 'date'

class Gmikul

    #コンストラクタ
    def initialize(addr,pass)
        @gmail = Gmail.new(addr,pass)
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

    #未読メールの差出人と件名を取得
    # Messageの配列を返す
    def getFromSub(lasttime)
        mail = Array.new
        @gmail.inbox.emails(:unread, :after => lasttime).map do |mes|
            begin
                s_from = mes.from[0]
                from = (s_from.name == nil ? "#{s_from.mailbox}#{s_from.host}" : s_from.name) + "さんから"
            rescue
                from = ''
            end
            begin
                subject = "「#{mes.subject.toutf8}」という件名の"
            rescue
                subject = ''
            end
            mail << Message.new(:message => "#{from}#{subject}メールが届いていますよ。", :system => true)
        end
        return mail
    end

    #ログアウト    
    def exit
    @gmail.primary.logout
    end
end


Plugin.create(:mikutter_gmikul) do
    #設定
    settings("Gmikul") do
        adjustment("更新間隔[sec]" , :gmikul_interval, 10, 3000)
        adjustment("未読を取得する日数" , :gmikul_days, 1, 30)
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
            mail = $gmikul.getFromSub($lasttime)
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
        config = YAML.load_file(File.join(File.dirname(__FILE__),"config.yaml"))
        begin  
            config = YAML.load_file(File.join(File.dirname(__FILE__),"config.yaml"))
            $gmikul = Gmikul.new(config["gmail"]["addr"],config["gmail"]["pass"])
        $lasttime = DateTime.now  - UserConfig[:gmikul_days].to_i
        count = $gmikul.haveUnread($lasttime)
        announce(maketext(count))
        mail = $gmikul.getFromSub($lasttime)
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
            mail = $gmikul.getFromSub($lasttime) 
            unless mail.empty? then
                announce(maketext(count))
                pushMailbox(mail)
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
