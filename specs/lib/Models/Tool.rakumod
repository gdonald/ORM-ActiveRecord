use ORM::ActiveRecord::Model;

unit module Models::Tool;

class Tool is Model is export {
  method table-name { 'bench_tools' }

  submethod BUILD {
    self.belongs-to: workshop => class-name => 'Workshop';

    self.validate: 'name', { :presence };
  }
}

GLOBAL::<Tool> := Tool;
