# -*- coding: utf-8 -*-
require 'gmail'
require 'yaml'
require 'kconv'
require 'date'

class Gmikul

    #コンストラクタ
    def initialize(addr,pass)
        @gmail = Gmail.new(addr,pass)
        #@mailはMessageとmessage_idのハッシュの配列
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
        @mail.each do |h|
            return true if h[:id] == message_id
        end
        return false
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
            unless mes.text_part && mes.html_part
                return mes.body.decoded.encode("UTF-8", mes.charset)
            else 
                if mes.text_part
                    return mes.text_part.decoded
                elsif mes.html_part
                    return mes.html_part.decoded
                end
            end
        rescue
            return nil
        end
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
            #未読状態の維持
            mes.mark(:unread)
            #Messageを作成 
            n_mail = Message.new(:message => text, :system => true)
            n_mail[:user] = User.new(
                                :id     => @id,
                                :idname => "Gmikul",
                                :name   => "mikuttter_Gmikul" ,
                                :profile_image_url => MUI::Skin.get("icon.png"))
            @mail << {post: n_mail, id: mes.message_id} 
            @id -= 1              
        end
        #Messageの配列を作成    
        mesary = Array.new
        @mail.each do |h|
            mesary << h[:post]
        end
        return mesary
    end

    #既読にする
    def doKidoku(target,lasttime)
        target.each do |del|
            @mail.each do |mail| 
                if mail[:post][:user][:id] == del[:user][:id] then
                    @gmail.inbox.emails(:unread, :after => lasttime).map do |tgt|
                        if tgt.message_id == mail[:id]
                            tgt.mark(:read)
                        end
                    end
                    @mail.delete(mail)
                end
            end
        end
        sleep 3
    end

    #ログアウト    
    def logout
    @gmail.logout
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
 
    #コマンドー
    command(:kidoku,
            name: "既読にする",
            condition: Plugin::Command[:HasMessage],
            visible: true,
            role: :timeline
    )do |msg|
        doKidoku(msg)
    end

    #既読にする
    def doKidoku(m)
        mail = Array.new
        m.messages.map do |msg|
            if msg.idname != "Gmikul" 
                announce("Gmail通知以外のツイートが選択されています。")
                return false
            end
            mail << msg
        end
        $gmikul.doKidoku(mail,$lasttime)
        doUpdate(true)
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

    #未読の取得と通知
    #引数 true => 0件の場合非表示 false => 0件でも表示
    def doUpdate(ifzero)
        count = $gmikul.haveUnread($lasttime)
        mail = $gmikul.genMessage($lasttime,UserConfig[:gmikul_body])
        announce(maketext(count)) unless ifzero && count == 0
        pushMailbox(mail)
        changeIcon(count)
    end

    #テキストを生成
    def maketext(count)
        return "未読メールの取得に失敗しました。" if(count < 0)
        return count == 0 ? "未読メールはありません。" : "#{count}件の未読メールがあります。"
    end

    #タブのアイコンを変える
    def changeIcon(count)
        if count == 0
            tab(:mikutter_gmikul).set_icon File.expand_path(File.join(File.dirname(__FILE__), 'gmail.png'))
        else
            tab(:mikutter_gmikul).set_icon File.expand_path(File.join(File.dirname(__FILE__), 'gmail_ur.png'))
        end
    end

    #起動時
    on_boot do 
        UserConfig[:gmikul_interval] ||= 180
        UserConfig[:gmikul_days] ||= 1 
        begin  
            config = YAML.load_file(File.join(File.dirname(__FILE__),"config.yaml"))
            $gmikul = Gmikul.new(config["gmail"]["addr"],config["gmail"]["pass"])
            $lasttime = DateTime.now  - UserConfig[:gmikul_days].to_i
            doUpdate(false)
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
            doUpdate(true)
            sleep 1
            autoUpdate
        }
    end
    
    #投稿ボックス、ゲットだぜ！
    def getPostbox
        filter_gui_postbox_post do |postbox|
            buf = ObjectSpace.each_object(Gtk::PostBox).to_a.first.widget_post.buffer
            if buf.text =~ /^@gmikul/ then
                doUpdate(false)
                clearBox(buf)        
            end
            [postbox]
        end
    end
    
    getPostbox
    autoUpdate
    
    at_exit{$gmikul.logout}
end
