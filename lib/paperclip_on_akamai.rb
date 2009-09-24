# PaperclipOnAkamai
module PaperclipOnAkamai

  class << self
    def included base #:nodoc:
      base.extend ClassMethods
    end
  end

  module ClassMethods
    # +has_attached_file+ gives the class it is called on an attribute that maps to a file. This
    # is typically a file stored somewhere on the filesystem and has been uploaded by a user. 
    # The attribute returns a Paperclip::Attachment object which handles the management of
    # that file. The intent is to make the attachment as much like a normal attribute. The 
    # thumbnails will be created when the new file is assigned, but they will *not* be saved 
    # until +save+ is called on the record. Likewise, if the attribute is set to +nil+ is 
    # called on it, the attachment will *not* be deleted until +save+ is called. See the 
    # Paperclip::Attachment documentation for more specifics. There are a number of options 
    # you can set to change the behavior of a Paperclip attachment:
    # * +url+: The full URL of where the attachment is publically accessible. This can just
    #   as easily point to a directory served directly through Apache as it can to an action
    #   that can control permissions. You can specify the full domain and path, but usually
    #   just an absolute path is sufficient. The leading slash *must* be included manually for 
    #   absolute paths. The default value is 
    #   "/system/:attachment/:id/:style/:basename.:extension". See
    #   Paperclip::Attachment#interpolate for more information on variable interpolaton.
    #     :url => "/:class/:attachment/:id/:style_:basename.:extension"
    #     :url => "http://some.other.host/stuff/:class/:id_:extension"
    # * +default_url+: The URL that will be returned if there is no attachment assigned. 
    #   This field is interpolated just as the url is. The default value is 
    #   "/:attachment/:style/missing.png"
    #     has_attached_file :avatar, :default_url => "/images/default_:style_avatar.png"
    #     User.new.avatar_url(:small) # => "/images/default_small_avatar.png"
    # * +styles+: A hash of thumbnail styles and their geometries. You can find more about 
    #   geometry strings at the ImageMagick website 
    #   (http://www.imagemagick.org/script/command-line-options.php#resize). Paperclip
    #   also adds the "#" option (e.g. "50x50#"), which will resize the image to fit maximally 
    #   inside the dimensions and then crop the rest off (weighted at the center). The 
    #   default value is to generate no thumbnails.
    # * +default_style+: The thumbnail style that will be used by default URLs. 
    #   Defaults to +original+.
    #     has_attached_file :avatar, :styles => { :normal => "100x100#" },
    #                       :default_style => :normal
    #     user.avatar.url # => "/avatars/23/normal_me.png"
    # * +whiny_thumbnails+: Will raise an error if Paperclip cannot post_process an uploaded file due
    #   to a command line error. This will override the global setting for this attachment. 
    #   Defaults to true. 
    # * +convert_options+: When creating thumbnails, use this free-form options
    #   field to pass in various convert command options.  Typical options are "-strip" to
    #   remove all Exif data from the image (save space for thumbnails and avatars) or
    #   "-depth 8" to specify the bit depth of the resulting conversion.  See ImageMagick
    #   convert documentation for more options: (http://www.imagemagick.org/script/convert.php)
    #   Note that this option takes a hash of options, each of which correspond to the style
    #   of thumbnail being generated. You can also specify :all as a key, which will apply
    #   to all of the thumbnails being generated. If you specify options for the :original,
    #   it would be best if you did not specify destructive options, as the intent of keeping
    #   the original around is to regenerate all the thumbnails when requirements change.
    #     has_attached_file :avatar, :styles => { :large => "300x300", :negative => "100x100" }
    #                                :convert_options => {
    #                                  :all => "-strip",
    #                                  :negative => "-negate"
    #                                }
    # * +storage+: Chooses the storage backend where the files will be stored. The current
    #   choices are :filesystem and :s3. The default is :filesystem. Make sure you read the
    #   documentation for Paperclip::Storage::Filesystem and Paperclip::Storage::S3
    #   for backend-specific options.
    def has_attached_file_on_akamai name, options = {}
      include InstanceMethods

      # Add Custom Akamai Url
      url = options[:url] || Paperclip::Attachment.default_options[:url]
      options[:url] = lambda { |a| a.instance.akamai_asset_url(url, name) }

      # Call Default Paperclip Setup
      has_attached_file name.to_sym, options
      
      attr_accessor :_do_akamai_upload

      define_method "upload_#{name}_to_akamai" do
        upload_to_akamai(name)
      end
      
      define_method "process_upload_#{name}_to_akamai" do
        process_upload_to_akamai(name)
      end
      
      define_method "do_akamai_upload_for_#{name}?" do
        do_akamai_upload?(name)
      end
      
      define_method "do_akamai_upload_for_#{name}=" do |value|
        do_akamai_upload(name,value)
      end
      
      define_method "randomize_#{name}_file_name" do 
        randomize_asset_file_name(name)
      end
      
      define_method "enable_#{name}_upload_to_akamai" do
        enable_upload_to_akamai(name)
      end

      # Generate Random Filename (Should solve purging problems)
      send("before_#{name}_post_process", :"randomize_#{name}_file_name")

      # Enable Upload to Akamai                            
      send("after_#{name}_post_process", :"enable_#{name}_upload_to_akamai")

      # Do Upload
      after_save :"process_upload_#{name}_to_akamai"
    end
    
  end

  module InstanceMethods #:nodoc:
    
    def do_akamai_upload?(name)
      @_do_akamai_upload ||= {}
      return @_do_akamai_upload[name]
    end
    
    def do_akamai_upload(name, value)
      @_do_akamai_upload ||= {}
      @_do_akamai_upload[name] = value
    end
    
    def process_upload_to_akamai(paperclip_attachment)
      if self.send("do_akamai_upload_for_#{paperclip_attachment}?") && PaperclipOnAkamai::CONFIG["enabled"] && self.send(paperclip_attachment).present?
        if PaperclipOnAkamai::CONFIG["delayed_job"]
          self.send_later("upload_#{paperclip_attachment}_to_akamai") 
        else
          self.send("upload_#{paperclip_attachment}_to_akamai")
        end
      end
    end
    
    def enable_upload_to_akamai(paperclip_attachment)
        self.send("do_akamai_upload_for_#{paperclip_attachment}=",true) # at this time the model hasn't an id, so say after_save callback we need to upload
        self.send("#{paperclip_attachment}_on_akamai=",false) # since something has changed, don't use akamai version until its properly updated
     end
    
    def upload_to_akamai(paperclip_attachment)
      begin
        self.send("#{paperclip_attachment}_on_akamai=",false)
        att = self.send(paperclip_attachment)
        Net::SSH.start(PaperclipOnAkamai::CONFIG["scp_host"], PaperclipOnAkamai::CONFIG["scp_user"], :keys => [PaperclipOnAkamai::CONFIG["key"]]) do |ssh|
          ssh.exec!("mkdir -p #{File.dirname(File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url.split("?").first))}")
          ssh.exec!("rm #{File.dirname(File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url.split("?").first))}/*")
          att.styles.each do |style,value|
            ssh.exec!("mkdir -p #{File.dirname(File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url(style).split("?").first))}")
            ssh.exec!("rm #{File.dirname(File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url.split("?").first))}/*")
          end
        end
        Net::SCP.start(PaperclipOnAkamai::CONFIG["scp_host"], PaperclipOnAkamai::CONFIG["scp_user"], :keys => [PaperclipOnAkamai::CONFIG["key"]]) do |scp|
          scp.upload!(att.path, File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url.split("?").first)) 
          att.styles.each do |style,value|
            scp.upload!(att.path(style), File.join(PaperclipOnAkamai::CONFIG["remote_path"],att.url(style).split("?").first)) 
          end
        end
        self.send("#{paperclip_attachment}_on_akamai=",true)
        self.save
      rescue Exception => e
        self.send("#{paperclip_attachment}_on_akamai=",false)
      end
    end

    def akamai_asset_url(url, paperclip_attachment)
      if PaperclipOnAkamai::CONFIG["enabled"] && self.send("#{paperclip_attachment}_on_akamai?")
        return PaperclipOnAkamai::CONFIG["web_host"]+"/"+PaperclipOnAkamai::CONFIG["remote_path"]+url
      else
        url
      end
    end

    def randomize_asset_file_name(paperclip_attachment) 
      extension = File.extname(self.send("#{paperclip_attachment}_file_name")) 
      filename = File.basename(self.send("#{paperclip_attachment}_file_name"), extension)
      self.send(paperclip_attachment).instance_write(:file_name, "#{filename}_#{ActiveSupport::SecureRandom.hex.first(8)}#{extension}") 
    end 
  end

end

autoload :ActiveRecord, 'activerecord'

# Set it all up.
if Object.const_defined?("ActiveRecord")
  ActiveRecord::Base.send(:include, PaperclipOnAkamai)
  PaperclipOnAkamai::CONFIG = YAML::load_file(File.join(RAILS_ROOT, 'config', 'akamai.yml'))[RAILS_ENV]
  PaperclipOnAkamai::CONFIG["key"] = File.join(RAILS_ROOT,PaperclipOnAkamai::CONFIG["key"]) if PaperclipOnAkamai::CONFIG["key"].present?
end


