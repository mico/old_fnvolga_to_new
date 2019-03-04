require_relative '../lib/migrate'

RSpec.describe 'migration' do
  let(:config) do
    { 'article' => { fields: { 'Title' => 'title' },
                     from: 'Articles',
                     to: 'fs_newspaper_article' } }
  end
  let(:config_with_relation) do
    { 'article' => { fields: { 'Title' => 'title', 'Issue' => 'newspaper_issue_id' },
                     from: 'Articles',
                     to: 'fs_newspaper_article',
                     relations: { 'Issue' => { type: 'belongs_to' } } },
      'issue' => { fields: { 'TotalNum' => 'number' },
                   from: 'Issues',
                   to: 'fs_newspaper_issue' }
    }
  end

  let(:migration) { Migration.new('article', config) }
  let(:migration_with_relation) { Migration.new('article', config_with_relation) }
  let(:migration_issue) { Migration.new('issue', config_with_relation, 1) }

  let(:row) { { 'Title' => 'just a title' } }
  let(:row_with_relation) { { 'Title' => 'just a title', 'Issue' => 1 } }
  let(:issue_row) { { 'TotalNum' => 3 } }

  let(:result) { "INSERT INTO fs_newspaper_article (`title`) VALUES ('just a title')" }
  let(:mappings) { { 'issue' => { 1 => 2 } } }
  let(:result_with_relation) do
    "INSERT INTO fs_newspaper_article (`title`, `newspaper_issue_id`) VALUES ('just a title', '2')"
  end
  let(:result_with_relation_with_new_issue_id) do
    "INSERT INTO fs_newspaper_article (`title`, `newspaper_issue_id`) VALUES ('just a title', '10')"
  end
  let(:result_for_issue) { "INSERT INTO fs_newspaper_issue (`number`) VALUES ('3')" }

  it 'should select data from database based on config' do
    expect(migration.make_query).to eq('SELECT Title FROM Articles limit 10')
    expect(migration.migrate_data([row]))
      .to eq([result])
  end

  it 'should return same amount of inserts as input data ' do
    expect(migration.migrate_data([row] * 2))
      .to eq([result] * 2)
  end

  it 'should return mapping relation id' do
    expect(migration_with_relation).to receive(:mappings).and_return(mappings)
    expect(migration_with_relation.migrate_data([row_with_relation])).to eq([result_with_relation])
  end

  # it 'should return relations ids' do
  #   expect(migration_with_relation).to receive(:get_data).and_return([row_with_relation])
  #   expect(migration_with_relation.relations_with_ids { |relations| relations.to_h }).to eq(['issue' => 1])
  # end

  it 'should return insert for new relation' do
    expect(migration_issue.migrate_data([issue_row])).to eq([result_for_issue])
  end

  it 'should select entity row from database based on config and entity id' do
    expect(migration_issue.make_query).to eq(format('SELECT TotalNum FROM Issues WHERE id = %<id>d',
                                                    id: row_with_relation['Issue']))
  end

  # it 'should return relation creation for every parent record' do
  #   expect(migration_with_relation).to receive(:get_data).and_return([row_with_relation])
  #   expect(migration_with_relation.relations_with_ids do |relations|
  #     relations.map do |relation_entity, entity_id|
  #       entity_migration = Migration.new(relation_entity, config_with_relation[relation_entity], entity_id)
  #       expect(entity_migration).to receive(:mappings).and_return({})
  #       expect(entity_migration.migrate_data([issue_row])).to eq([result_for_issue])
  #     end
  #   end.count).to eq(1)
  # end

  it 'should return INSERT INTO Issue ... for each INSERT INTO Article for belongs_to relation' do
    # expect(migration_with_relation).to receive(:get_data).and_return([row_with_relation])
    expect_any_instance_of(Migration).to receive(:get_data).with('SELECT TotalNum FROM Issues WHERE id = 1')
                                                           .and_return([issue_row])
    expect(migration_with_relation).to receive(:update_data)
      .with("INSERT INTO fs_newspaper_issue (`number`) VALUES ('3')").and_return(10)
    expect(migration_with_relation.migrate_data([row_with_relation]))
      .to eq(["INSERT INTO fs_newspaper_article (`title`, `newspaper_issue_id`) VALUES ('just a title', '10')"])
  end

  # it 'should substitute new id for relation entity'
  # it 'should not create new id for mapped relation entity'
  # it 'should not create new id for existing relation entity'

  # it 'should return inserts for relation / parent / manytomany table for manytomany relations'
  # belongs_to
  # should return:
  # INSERT INTO Issue ... for each INSERT INTO Article
  # ^^ run and collect original_issue_id => new_issue_id
  # INSERT INTO Articles ...
  # ^^ substitude issue ids

  # manytomany
  # INSERT INTO author ... FOR EACH Uniq Author
  # ^^ run and collect original_author_id => new_author_id
  # INSERT INTO Articles ...
  # ^^ run and collect original_article_id => new_article_id
  # INSERT INTO article_authors ... FOR EACH INSERT INTO Article
  # ^^ substitute author and article ids

  # should return data row by row, like:
  # migration.get_data_row do |row| # yield(row) in get_data_row
  #   make_queries_by(row)
  # end

end
