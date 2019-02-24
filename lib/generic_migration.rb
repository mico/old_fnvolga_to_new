class GenericMigration
  def relations
    @config[:relations] || {}
  end
end