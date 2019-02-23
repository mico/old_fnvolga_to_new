require_relative '../lib/migrate'

RSpec.describe 'migration' do
  let(:config) { { fields: { 'Title' => 'title' }, from: 'Articles' } }
  let(:config_with_relation) do
    { fields: { 'Title' => 'title', 'Issue' => 'newspaper_issue_id' },
      from: 'Articles',
      relations: { 'Issue' => { type: 'onetomany' } } }
  end
  let(:migration) { Migration.new('article', config) }
  let(:migration_with_relation) { Migration.new('article', config_with_relation) }
  let(:row) { { 'Title' => 'just a title' } }
  let(:row_with_relation) { { 'Title' => 'just a title', 'Issue' => 1 } }
  let(:result) { "INSERT INTO  (`title`) VALUES ('just a title')" }
  let(:mappings) { { 'issue' => { 1 => 2 } } }
  let(:result_with_relation) { "INSERT INTO  (`title`, `newspaper_issue_id`) VALUES ('just a title', '2')" }

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
end
