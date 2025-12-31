class CreateTasks < ActiveRecord::Migration[8.1]
  def change
    create_table :tasks do |t|
      t.text :content

      t.timestamps
    end
  end
end
