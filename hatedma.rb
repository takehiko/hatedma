#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

# hatedma.rb : Hatena Diary Manager
#   by takehikom (http://d.hatena.ne.jp/takehikom/)

if RUBY_VERSION < "1.9"
  $KCODE = "u"
end

require "optparse"
require "fileutils"
require "pstore"
require "singleton"

HATENA_USERNAME = "hatenausername"
DATA_DIR = File.expand_path("~/.hatedma")

module HatenaDiaryManager
  class Config
    include Singleton
    attr_accessor :base_dir, :username, :user_dir
    attr_accessor :dir_diary, :dir_diary_old, :file_tag, :file_tag_old
    attr_accessor :file_amazon, :file_list_title, :file_list_date
    attr_accessor :file_list_wiki
    attr_accessor :file_diary

    def setup(h = {})
      return if @initialized && !h.key?(:force_init)
      @initialized = true

      @base_dir = h[:data_dir] || DATA_DIR
      @username = h[:username] || ENV["HATENA_USERNAME"] || HATENA_USERNAME
      @user_dir = "#{@base_dir}/#{@username}"

      unless test(?d, @base_dir)
        FileUtils.mkdir_p(@base_dir, :verbose => true)
      end
      if @base_dir != @user_dir && !test(?d, @user_dir)
        FileUtils.mkdir_p(@user_dir, :verbose => true)
      end

      @dir_diary = "#{@user_dir}/data"
      @dir_diary_old = "#{@dir_diary}.old"
      @file_tag = "#{@user_dir}/tag.pstore"
      @file_tag_old = "#{@file_tag}.old"
      @file_amazon = "#{@base_dir}/amazon.pstore"
      # @file_amazon = "#{@user_dir}/amazon.pstore"
      @file_list_title = "#{@user_dir}/#{@username}_title.txt"
      @file_list_date = @file_list_title.sub(/_title.txt$/, "_date.txt")
      @file_list_wiki = @file_list_title.sub(/_title.txt$/, "_wiki.txt")
      @file_diary = find_diary_file

      self
    end

    def find_diary_file
      files = []
      dirs = ["."]
      dirs << @user_dir << @base_dir
      filenames = [@username, "#{@username}.xml", "#{@username}.xml.gz"]

      dirs.each do |dir|
        filenames.each do |filename|
          path = "#{dir}/#{filename}"
          if test(?f, path)
            files << path
          end
        end
      end

      case files.size
      when 0
        @username
      when 1
        files.first
      else
        files.sort_by {|item| File.mtime(item).to_i}.last
      end
    end

    def print_status
      {:base_dir => "base directory",
        :username => "user name of hatena",
        :user_dir => "user's directory",
        :dir_diary => "directory of diary files",
        :dir_diary_old => "directory of diary files (backup)",
        :file_tag => "tags and entries (PStore)",
        :file_tag_old => "tag and entries (PStore, backup)",
        :file_amazon => "product/book info (PStore)",
        :file_list_title => "list of URLs, tags and titles",
        :file_list_date => "list of URLs, dates and titles",
        :file_list_wiki => "list of URLs for Wiki link",
        :file_diary => "log file to be analized",
      }.each_pair do |sym, str|
        puts "-- #{str}"
        puts "#{sym} = #{send(sym)}"
        puts
      end
    end
  end

  class Master
    def initialize(h = {})
      @opt = h
      @action = h[:action]
      @output_type = h[:output_type] || :url
      @tag_h = {}
      setup_config(h)
    end

    def start
      case @action
      when :analyze
        action_analyze
      when :analyze_amazon
        action_analyze_amazon
      when :search
        action_search
      when :search_tag
        action_search_tag
      when :tag_all
        action_tag_all
      when :artstat
        action_article_stat
      else
        puts "Ignored. Please specify one of -A/-S/-T/-G!"
        exit
      end
    end

    def setup_config(h)
      c = HatenaDiaryManager::Config.instance
      c.setup(h)
      @base_dir = c.base_dir
      @username = c.username
      @user_dir = c.user_dir
      @dir_diary = c.dir_diary
      @dir_diary_old = c.dir_diary_old
      @file_tag = c.file_tag
      @file_tag_old = c.file_tag_old
      @file_amazon = c.file_amazon
      @file_list_title = c.file_list_title
      @file_list_date = c.file_list_date
      @file_list_wiki = c.file_list_wiki
      @file_diary = c.file_diary
    end

    def action_analyze
      refresh_dirfile
      puts "Diary file: #{@file_diary}"
      f_out_title = open(@file_list_title, "w")
      f_out_date = open(@file_list_date, "w")
      f_out_wiki = open(@file_list_wiki, "w")

      if /\.gz$/ =~ @file_diary
        command_pre = "|zcat "
      else
        command_pre = ""
      end

      art = nil
      open(command_pre + @file_diary) do |f_in|
        f_in.each_line do |line0|
          line = line0.reduce_amp
          if /^\*([0-9]{10,})\*\s*(.*)$/ =~ line
            utime, title0 = $1, $2
            if /^\[.+\]/ =~ title0
              tag, title = $&, $'.strip
              tag_comment = " <!-- #{tag} -->"
            else
              tag, title = "", title0
              tag_comment = ""
            end
            if art
              art.body = art.body.sub(/<\/body>.*\z/m, "")
              art.save(true)
            end
            art = HatenaDiaryManager::Article.new(utime)
            art.body = line
            find_tag(line, utime)
            date_tag_comment = "<!-- #{art.ymd}#{tag.empty? ? '' : ' '}#{tag} -->"

            print <<EOS if $DEBUG
URL:    #{art.url}
title0: #{title0}
tag:    #{tag}
tagcom: #{tag_comment}
dtcom:  #{date_tag_comment}
title:  #{title}
utime:  #{utime}
time:   #{art.time}
ymd:    #{art.ymd}
file:   #{art.file}
line:   #{line}
EOS

            # [http://d.hatena.ne.jp/takehikom/20120113/1326401059:title=hatedma: はてなダイアリーマネジャー]<!-- 2012年1月13日 [hatedma][Ruby] -->
            f_out_title.print "[#{art.url}:title=#{title}]#{date_tag_comment}\r\n"

            # [http://d.hatena.ne.jp/takehikom/20120113/1326401059:title=2012年1月13日]<span class="deco" style="font-size:xx-small;">（hatedma: はてなダイアリーマネジャー）</span> <!-- [hatedma][Ruby] -->
            f_out_date.print "[#{art.url}:title=#{art.ymd}]<span class=\"deco\" style=\"font-size:xx-small;\">（#{title}）</span>#{tag_comment}\r\n"

            # [[hatedma: はてなダイアリーマネジャー>http://d.hatena.ne.jp/takehikom/20120113/1326401059]]// 2012年1月13日 [hatedma][Ruby]
            f_out_wiki.print "[[#{title}>#{art.url}]]//#{date_tag_comment}\r\n"

          elsif art
            art.body += line
            find_tag(line, art.utime)
          end
        end
      end

      art.save(true) if art
      save_tag

      f_out_title.close
      f_out_date.close
      f_out_wiki.close
    end

    def find_tag(s, utime)
      s.scan(/\[.*?\]/) do |p1|
        p2 = p1[1...-1]
        tagname = ""
        case p2
        when /^https?:/, /^(isbn)|(asin)|(google):/i
          tagname = p2.split(/:/)[0, 2].join(":")
        when /^f:id:/
          tagname = p2.split(/:/)[0, 4].join(":")
        when /^id:/
          a = p2.split(/:/)
          a.pop if a.size > 3 && "image;:;detail".index(a[-1])
          tagname = a.join(":")
        else
          tagname = p2
        end
        unless tagname.empty?
          add_tag(tagname, utime)
          if $DEBUG
            puts "find tag: #{tagname}"
          end
        end
      end
    end

    def add_tag(name, utime)
      if @tag_h.key?(name)
        if @tag_h[name][-1] != utime
          @tag_h[name] << utime
        end
      else
        @tag_h[name] = [utime]
      end
    end

    def save_tag
      db = PStore.new(@file_tag)
      db.transaction do
        db["tag"] = @tag_h
      end
    end

    def load_tag
      db = PStore.new(@file_tag)
      db.transaction(true) do
        if db.root?("tag")
          @tag_h = db["tag"]
        else
          @tag_h = {}
        end
      end
    end

    def save_amazon
      db = PStore.new(@file_amazon)
      db.transaction do
        db["amazon"] = @amazon_h
      end
    end

    def load_amazon
      db = PStore.new(@file_amazon)
      db.transaction(true) do
        if db.root?("amazon")
          @amazon_h = db["amazon"]
        else
          @amazon_h = {}
        end
      end
    end

    def refresh_dirfile
      if test(?d, @dir_diary_old)
        FileUtils.remove_dir(@dir_diary_old, :verbose => true)
      end
      if test(?f, @file_tag_old)
        FileUtils.rm(@file_tag_old, :verbose => true)
      end
      if test(?d, @dir_diary)
        FileUtils.mv(@dir_diary, @dir_diary_old, :verbose => true)
      end
      if test(?f, @file_tag)
        FileUtils.mv(@file_tag, @file_tag_old, :verbose => true)
      end
    end

    def action_search
      word = @opt[:search_word]
      if !(String === word) || word.empty?
        puts "Ignored. Search word should be correctly specified."
        exit
      end

      glob = @dir_diary
      if @opt.key?(:search_date)
        case @opt[:search_date]
        when /^\d{4}$/
          glob += "/#{$&}/*/*.txt"
        when /^(\d{4})\/?(\d{2})$/
          glob += "/#{$1}/#{$2}"
        else
          puts "Ignored. Date should be either one of \"YYYY\" or \"YYYYMM\"."
          exit
        end
      else
        glob += "/*/*/*.txt"
      end

      art_a = []
      Dir.glob(glob) do |filename|
        next if test(?d, filename)
        open(filename) do |f_in|
          body = f_in.read
          if body.index(word)
            art_a << HatenaDiaryManager::Article.new(filename, @output_type == :body)
          end
        end
      end

      art_a.each do |art|
        art.print_info(@output_type)
      end
    end

    def action_search_tag
      load_tag

      tag = @opt[:search_tag]
      if !(String === tag) || tag.empty?
        puts "Ignored. Search word should be correctly specified."
        exit
      end

      # exact search
      if @tag_h.key?(tag)
        print_tag_entry(tag, false)
        return
      end

      # prefix search
      @tag_h.keys.sort.each do |key|
        if key.index(tag) == 0
          print_tag_entry(key)
        end
      end

      # isbn/asin search
      %w(isbn asin).each do |prefix|
        key = [prefix, tag].join(":")
        if @tag_h.key?(key)
          print_tag_entry(key)
          return
        end
      end
    end

    def print_tag_entry(key, flag_print_tag = true)
      puts "[#{key}]" if flag_print_tag
      @tag_h[key].each do |utime|
        art = HatenaDiaryManager::Article.new(utime, @output_type == :body)
        art.print_info(@output_type)
      end
    end

    def action_tag_all
      load_tag
      @tag_h.keys.sort.each do |key|
        print_tag_entry(key)
      end
    end

    def action_analyze_amazon
      self.extend HatenaDiaryManager::AmazonSearcher
      setup

      period = 5
      count = 0

      load_tag
      if @tag_h.empty?
        puts "action_analyze_amazon: do nothing"
        return
      end
      load_amazon

      @tag_h.each_key do |tag|
        unless /^(isbn)|(asin):/ =~ tag
          puts "#{tag}: skipped because it is not an Amazon item"
          next
        end
        code = tag.split(/:/)[1]
        if @amazon_h.key?(code)
          puts "#{tag}: skipped because it was already examined"
          next
        end
        h = search(code)
        @amazon_h[code] = h
        puts "#{tag} => #{h}"

        count += 1
        if count % period == 0
          save_amazon
        end
        sleep 3
      end

      if count % period > 0
        save_amazon
      end
    end

    def action_article_stat
      tag_stat = {} # tag_name => [entries, line, byte_size, char_size]

      Dir.glob("#{@dir_diary}/**/*.txt") do |filename|
        body = open(filename).read
        if /^\*[0-9]+\*\s*(.*)$/ =~ body
          title = $1
          tag_a = title.scan(/\[.*?\]/)
          if tag_a.empty?
            tag_a = ["(nonsection)"]
          else
            tag_a.map! {|item| item[1...-1]}
          end
          tag_a << "(total)"

          line = body.scan(/\n/).size
          byte_size = body.bytesize
          char_size = body.split(//).size

          tag_a.each do |t|
            if tag_stat.key?(t)
              tag_stat[t][0] += 1
              tag_stat[t][1] += line
              tag_stat[t][2] += byte_size
              tag_stat[t][3] += char_size
            else
              tag_stat[t] = [1, line, byte_size, char_size]
            end
          end
        end
      end

      puts "files lines byte_size char_size tag"
      tag_stat.keys.sort_by {|key| "%05d%08d" % [tag_stat[key][0], tag_stat[key][2]]}.reverse.each do |key|
        puts "#{tag_stat[key].join(' ')} #{key}"
      end
    end
  end

  class Article
    def initialize(param, opt_load = false)
      @utime = 0
      case param
      when Numeric
        @utime = param
      when /^\d+$/
        @utime = $&.to_i
      when /http.*\/(\d+)$/
        @utime = $1.to_i
      when /(\d+)\.txt$/
        @utime = $1.to_i
      else
        raise "utime not found: #{param}"
      end

      c = HatenaDiaryManager::Config.instance
      @time = Time.at(utime)
      @url = @time.strftime("http://d.hatena.ne.jp/#{c.username}/%Y%m%d/#{utime}")
      @file = @time.strftime("#{c.dir_diary}/%Y/%m/%d_#{utime}.txt")
      @ymd = "#{@time.year}年#{@time.month}月#{@time.day}日"
      # @ymd = @time.strftime("%Y年%m月%d日")
      @body = ""
      @loaded = false
      load if opt_load
    end

    attr_reader :utime, :url, :time, :ymd
    attr_accessor :file

    def body
      @body
    end

    def body=(s)
      @loaded = false
      @body = s
    end

    def load
      @loaded = true
      begin
        open(@file) do |f_in|
          @body = f_in.read
        end
      rescue
        @body = ""
      end
    end

    def save(opt_verbose)
      FileUtils.mkdir_p(File.dirname(@file))
      open(@file, "w") do |f_out|
        f_out.print @body
      end
      puts "saved: #{@file}" if opt_verbose
    end

    def print_info(output_type = :url)
      case output_type
      when :url
        puts @url
      when :file
        puts @file
      when :body
        puts "--"
        puts "-- #{@file} --"
        puts "--"
        print @body
      end
    end
  end

  module AmazonSearcher
    def setup
      # run "gem install ruby-aaws"
      # and prepare "~/.amazonrc"
      require "rubygems"
      require "amazon/aws/search"
    end

    def search(code, h = {})
      HatenaDiaryManager::Config.instance.setup(h)

      unless h.key?(:force_access)
        res_h = search_by_file_amazon(code)
        return res_h unless res_h.empty?
      end
      if /^[0-9A-Z]{10}$/ =~ code
        res_h = search_by_asin(code)
      else
        res_h = search_by_isbn(code)
      end
      if h.key?(:save_amazon) && !res_h.empty?
        save_file_amazon(code, res_h)
      end
      res_h
    end

    def search_by_isbn(code)
      a = Amazon::AWS::ItemSearch.new("Books", {"Keywords" => code})
      a.response_group = Amazon::AWS::ResponseGroup.new(:Medium)
      req = Amazon::AWS::Search::Request.new
      begin
        res = req.search(a)
        get_property(res.item_search_response.items.item.first)
      rescue
        Hash.new
      end
    end

    def search_by_asin(code)
      a = Amazon::AWS::ItemLookup.new("ASIN", {"ItemId" => code})
      a.response_group = Amazon::AWS::ResponseGroup.new(:Medium)
      req = Amazon::AWS::Search::Request.new
      begin
        res = req.search(a)
        get_property(res.item_lookup_response.items.item.first)
      rescue
        Hash.new
      end
    end

    def get_AWSObject_attr(item, level = 0)
      vars = item.instance_variables.delete_if { |c| c == :@__val__ || c == :@attrib }
      nl_idt = ("\n" + "  " * level)
      if item.is_a?(Array)
        item.map { |c| (item.length > 1 ? nl_idt : "") + get_AWSObject_attr(c, level + 1)}.join
      elsif !vars.empty?
        vars.map { |var|
          nl_idt + var.to_s + " = " +
          get_AWSObject_attr(item.instance_variable_get(var), level + 1)
        }.join.gsub(/(\n\s*)+\n/m, "\n")
      else
        item.to_s
      end
    end

    def get_property(item)
      asin = item.asin.to_s
      attr = item.item_attributes.first.to_h
      attr.each_key do |key|
        attr[key] = get_AWSObject_attr(attr[key], 1)
      end
      attr["asin"] ||= asin
      attr
    end

    def print_property(attr)
      attr.each_pair do |key, value|
        if /^ / =~ value
          print "#{key}:"
          puts value
        else
          puts "#{key}: #{value}"
        end
      end

      if /book/i =~ attr["product_group"]
        puts
        if /^97[89]/ =~ attr["ean"]
          puts "[isbn:#{attr['ean']}]"
        end
        title = attr["title"].gsub(/[\s　]/, "")
        puts "><a name=\"#{title}\">"
        puts "</a><"
        puts "\##{title}"

      if attr.key?("asin")
        puts
        asin = attr["asin"]
        puts "[asin:#{asin}]"
        puts "http://www.amazon.co.jp/dp/#{asin}"
      end
    end

    def search_by_file_amazon(code)
      db = PStore.new(HatenaDiaryManager::Config.instance.file_amazon)
      db.transaction(true) do
        return Hash.new unless db.root?("amazon")
        amazon_h = db["amazon"]
        return amazon_h[code] || Hash.new
      end
    end

    def save_file_amazon(code, res_h)
      db = PStore.new(HatenaDiaryManager::Config.instance.file_amazon)
      db.transaction do
        if db.root?("amazon")
          amazon_h = db["amazon"]
        else
          amazon_h = {}
        end
        amazon_h[code] = res_h
        db["amazon"] = amazon_h
      end
    end
  end
end

class String
  @@amp_h = {
    "amp" => "&",
    "gt" => ">",
    "lt" => "<",
    "quot" => '"'
  }

  def reduce_amp
    self.gsub(/&(\w+);/) {w=$1; @@amp_h.key?(w) ? @@amp_h[w] : w}
  end
end

if __FILE__ == $0
  opt = OptionParser.new
  h = {}

  opt.on("-A", "--analyze", "analyze log file") {
    h[:action] = :analyze
  }
  opt.on("-S", "--search=VAL", "search entries") {|v|
    h[:action] = :search
    h[:search_word] = v
  }
  opt.on("-T", "--tag=VAL", "search by tag") {|v|
    h[:action] = :search_tag
    h[:search_tag] = v
  }
  opt.on("-G", "--tag-all", "print all tags") {
    h[:action] = :tag_all
  }
  opt.on("-B", "--analyze-amazon", "examine Amazon products (with Ruby/AWS)") {
    h[:action] = :analyze_amazon
  }
  opt.on("-W", "--search-amazon=VAL", "search by ASIN (with Ruby/AWS)") {|v|
    h[:action] = :aws
    h[:asin] = v
  }
  opt.on("-E", "--status", "print directory and file names") {
    h[:action] = :status
  }
  opt.on("-K", "--artstat", "print statistics of articles") {
    h[:action] = :artstat
  }
  opt.on("-n", "--name=VAL", "hatena user name") {|v|
    h[:username] = v
  }
  opt.on("-d", "--dir=VAL", "data directory") {|v|
    h[:data_dir] = v
  }
  opt.on("-r", "--date=VAL", "scope of search") {|v|
    h[:search_date] = v
  }
  opt.on("-u", "--url", "print URLs") {
    h[:output_type] = :url
  }
  opt.on("-f", "--file", "print file paths") {
    h[:output_type] = :file
  }
  opt.on("-b", "--body", "print body texts") {
    h[:output_type] = :body
  }
=begin
  opt.on("-IT", "--import-tag=VAL", "import tags") {}
  opt.on("-OT", "--export-tag=VAL", "export tags") {}
  opt.on("-IA", "--import-amazon=VAL", "import product/book info") {}
  opt.on("-OA", "--export-amazon=VAL", "export product/book info") {}
=end

  opt.parse!(ARGV)
  case h[:action]
  when :aws
    h[:save_amazon] = true
    include HatenaDiaryManager::AmazonSearcher
    setup
    puts "<begin search:#{h[:asin]}>"
    print_property(search(h[:asin], h))
    puts "<end search:#{h[:asin]}>"
    exit
  when :status
    HatenaDiaryManager::Config.instance.setup(h).print_status
    exit
  end
  HatenaDiaryManager::Master.new(h).start
end
