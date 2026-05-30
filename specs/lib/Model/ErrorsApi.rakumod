use ORM::ActiveRecord::Model;

unit module Model::ErrorsApi;

class Banquet is Model is export {
  method table-name { 'concerts' }

  submethod BUILD {
    self.validate: 'name',  { :presence }
    self.validate: 'score', { numericality => { gt => 0 } }
  }
}

GLOBAL::<Banquet> := Banquet;
