use ORM::ActiveRecord::Model;

unit module Models::TenantNote;

class TenantNote is Model is export {
  method table-name { 'tenant_notes' }
}

TenantNote.query-constraints('tenant_id', 'id');

GLOBAL::<TenantNote> := TenantNote;
