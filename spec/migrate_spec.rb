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
  let(:migration) { Migration.new('article', config['article']) }
  let(:migration_with_relation) { Migration.new('article', config_with_relation['article']) }
  let(:row) { { 'Title' => 'just a title' } }
  let(:row_with_relation) { { 'Title' => 'just a title', 'Issue' => 1 } }
  let(:issue_row) { { 'TotalNum' => 3 } }
  let(:result) { "INSERT INTO fs_newspaper_article (`title`) VALUES ('just a title')" }
  let(:mappings) { { 'issue' => { 1 => 2 } } }
  let(:result_with_relation) do
    "INSERT INTO fs_newspaper_article (`title`, `newspaper_issue_id`) VALUES ('just a title', '2')"
  end
  let(:result_for_relation) { "INSERT INTO fs_newspaper_issue (`number`) VALUES ('3')" }

  it 'should migrate data based on config' do
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

  it 'should return relations ids' do
    expect(migration_with_relation).to receive(:get_data).and_return([row_with_relation])
    expect(migration_with_relation.relations_with_ids).to eq(['issue' => 1])
  end

  it 'should return insert for new relation' do
    #expect(MigrationRow.migrate_entity('issue', 1)).to eq(result_for_relation)
  end
end
