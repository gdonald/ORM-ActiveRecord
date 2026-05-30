use ORM::ActiveRecord::Model;

unit module Model::ErrorsApi;

class ErrPhevent is Model is export {
  method table-name { 'phevents' }

  submethod BUILD {
    self.validate: 'name',  { :presence }
    self.validate: 'score', { numericality => { gt => 0 } }
  }
}

GLOBAL::<ErrPhevent> := ErrPhevent;
