generic
   type Element is private;
   type Index is mod <>;
package generic_protected_queue is

   type List is array (Index) of Element;
   type Queue_type is record
      Top, Free : Index := Index'First;
      Is_Empty : Boolean := True;
      Elements : List;
   end record;

   protected type Protected_Queue is
      entry     Enqueue (Item : Element);
      entry     Dequeue (Item : out Element);
      procedure Empty_Queue;
      function  Is_empty   return Boolean;
      function  Is_Full    return Boolean;
      function  Queue_Size return Natural;
   private
      Queue : Queue_type;
   end Protected_Queue;

end generic_protected_queue;
