use ORM::ActiveRecord::Model;

unit module Models::Workshop;

class Workshop is Model is export {
  submethod BUILD {
    self.has-many: tools     => class-name => 'Tool';
    self.has-one:  signboard => class-name => 'Signboard';

    self.validate: 'name', { :presence };

    self.accepts-nested-attributes-for: 'tools',
      allow-destroy => True,
      limit         => 5,
      reject-if     => -> %a { (%a<name> // '').trim eq '' };

    self.accepts-nested-attributes-for: 'signboard',
      update-only => True;
  }
}

GLOBAL::<Workshop> := Workshop;
