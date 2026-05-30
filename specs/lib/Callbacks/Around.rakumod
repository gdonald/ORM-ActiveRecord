use ORM::ActiveRecord::Model;

unit module Callbacks::Around;

our @events is export = ();

class Client is Model is export {
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.around-save: -> &yield {
      @events.push: 'around-save-before';
      &yield();
      @events.push: 'around-save-after';
    };
    self.around-create: -> &yield {
      @events.push: 'around-create-before';
      &yield();
      @events.push: 'around-create-after';
    };
    self.around-update: -> &yield {
      @events.push: 'around-update-before';
      &yield();
      @events.push: 'around-update-after';
    };
    self.around-destroy: -> &yield {
      @events.push: 'around-destroy-before';
      &yield();
      @events.push: 'around-destroy-after';
    };
    self.before-save:   -> { @events.push: 'before-save' };
    self.after-save:    -> { @events.push: 'after-save'  };
    self.before-create: -> { @events.push: 'before-create' };
    self.after-create:  -> { @events.push: 'after-create'  };
    self.before-update: -> { @events.push: 'before-update' };
    self.after-update:  -> { @events.push: 'after-update'  };
    self.before-destroy: -> { @events.push: 'before-destroy' };
    self.after-destroy:  -> { @events.push: 'after-destroy'  };
  }
}

class HaltClient is Model is export {
  method table-name { 'clients' }
  submethod BUILD {
    self.validate: 'email', { :presence };
    self.around-save: -> &yield {
      # never yield → halts
    };
  }
}

GLOBAL::<Client> := Client;
GLOBAL::<HaltClient> := HaltClient;
