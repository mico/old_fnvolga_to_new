require_relative '../lib/migrate'

RSpec.describe 'migration' do
  let(:config) { { fields: { Title: 'title' }, from: 'Articles' } }
  let(:migration) { Migration.new('article', config) }
  let(:row) { { 'Title': 'just a title' } }
  let(:result) { "INSERT INTO  (`title`) VALUES ('just a title')" }

  it 'should migrate data based on config' do
    expect(migration.make_query).to eq('SELECT Title FROM Articles limit 10')
    expect(migration.migrate_data({}, [row]))
      .to eq([result])
  end

  it 'should return same amount of inserts as input data ' do
    expect(migration.migrate_data({}, [row] * 2))
      .to eq([result] * 2)
  end
end
