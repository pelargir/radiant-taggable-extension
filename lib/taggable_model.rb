module TaggableModel      # for inclusion into ActiveRecord::Base
  
  def self.included(base)
    base.extend ClassMethods
    base.class_eval {
      @@taggable_models = []
      cattr_accessor :taggable_models
    }
  end

  module ClassMethods
    def is_taggable?
      false
    end

    def is_taggable
      return if is_taggable?

      has_many :taggings, :as => :tagged
      has_many :attached_tags, :through => :taggings, :source => :tag    # can't be just has_many :tags because that stomps on the radius tags in Page.
      
      named_scope :from_tags, lambda { |tags| 
        {
          :joins => "INNER JOIN taggings on taggings.tagged_id = #{self.table_name}.id AND taggings.tagged_type = '#{self.to_s}'", 
          :conditions => ["taggings.tag_id in(#{tags.map{ '?' }.join(',')})"] + tags.map(&:id),
          :group => column_names.map { |n| table_name + '.' + n }.join(','),    # postgres is strict and requires that we group by all selected (but not aggregated) columns
          :order => "count(taggings.id) DESC"
        }
      }

      named_scope :from_all_tags, lambda { |tags| 
        {
          :joins => "INNER JOIN taggings on taggings.tagged_id = #{self.table_name}.id AND taggings.tagged_type = '#{self.to_s}'", 
          :conditions => ["taggings.tag_id in(#{tags.map{ '?' }.join(',')})"] + tags.map(&:id),
          :group => column_names.map { |n| table_name + '.' + n }.join(','),    # postgres is strict and requires that we group by all selected (but not aggregated) columns
          :having => "count(taggings.id) >= #{tags.length}"
        }
      } do
        # count is badly sugared here: it omits the group and having clauses.
        # length performs the query and looks at the array: less neat, but more right
        # this gives us back any? and empty? as well.
        def count
          length
        end
      end
      
      # this sets up eg Taggings.of_model
      # and then uses that to define instance methods in Tag:
      # tag.models
      # tag.models_count
      Tag.define_class_retrieval_methods(self.to_s)
      
      class_eval {
        extend TaggableModel::TaggableClassMethods
        include TaggableModel::TaggableInstanceMethods
        alias_method "related_#{self.to_s.underscore.pluralize}".intern, :related
        alias_method "closely_related_#{self.to_s.underscore.pluralize}".intern, :closely_related
      }

      ActiveRecord::Base.taggable_models.push(self.to_s.intern)
    end
  end

  module TaggableClassMethods
    def tagged_with(somewords='')
      if somewords.blank?
        []
      elsif somewords.is_a?(Array)
        self.from_all_tags(somewords)
      else
        self.from_all_tags( Tag.from_list(somewords) )
      end
    end

    def is_taggable?
      true
    end
    
    def tags_for_cloud_from(these, limit=50)
      Tag.attached_to(these).most_popular(limit)   # here popularity is use-count *within the group*
    end
  end
  
  module TaggableInstanceMethods

    def add_tag(word=nil)
      self.attached_tags << Tag.for(word) if word && !word.blank?
    end

    def remove_tag(word=nil)
      tag = Tag.find_by_title(word) if word && !word.blank?
      self.attached_tags.delete(tag) if tag
    end
    
    def related
      self.attached_tags.empty? ? [] : self.class.from_tags(self.attached_tags) - [self]
    end
    
    def closely_related
      self.attached_tags.empty? ? [] : self.class.from_all_tags(self.attached_tags) - [self]
    end
    
    # in the case of pages and anything else that keywords in the same way this overrides the existing column
    # the rest of the time it's just another way of specifying tags.
    
    def keywords 
      self.attached_tags.map {|t| t.title}.join(', ')
    end
    
    def keywords=(somewords="")
      if somewords.blank?
        self.attached_tags.clear
      else
        self.attached_tags = Tag.from_list(somewords)
      end
    end
    
    def keywords_before_type_cast   # for form_helper
      keywords
    end
    
    def tags_from_keywords
      if self.class.column_names.include?('keywords') && keys = read_attribute(:keywords)
        self.attached_tags = Tag.from_list(keys) || []
      end
    end
    
  end
end

