class GenericMigration
  def relations
    @config[:relations] || {}
  end

  def manytomany_relations
    relations.select do |_, params|
      params[:type] == 'manytomany' or params[:convert_to] == 'manytomany'
    end
  end
end
