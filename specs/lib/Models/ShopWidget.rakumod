use ORM::ActiveRecord::Model;

unit module Models::ShopWidget;

class ShopWidget is Model is export {
  method table-name { 'shop_widgets' }
}

ShopWidget.primary-key('shop_id', 'id');

GLOBAL::<ShopWidget> := ShopWidget;
