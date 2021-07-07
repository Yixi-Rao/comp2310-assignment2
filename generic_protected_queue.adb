package body generic_protected_queue is

   protected body Protected_Queue is

      function Is_Empty return Boolean is (Queue.Is_Empty);
      function Is_Full return Boolean is
        (not Queue.Is_Empty and then Queue.Top = Queue.Free);

      function Queue_Size return Natural is
      begin
         return Natural (Queue.Free - Queue.Top + 1);
      end Queue_Size;

      entry  Enqueue (Item : Element) when not Is_Full is
      begin
         Queue.Elements (Queue.Free) := Item;
         Queue.Free := Index'Succ (Queue.Free);
         Queue.Is_Empty := False;
      end Enqueue;

      entry Dequeue (Item : out Element) when not Is_empty is
      begin
         Item := Queue.Elements (Queue.Top);
         Queue.Top := Index'Succ (Queue.Top);
         Queue.Is_Empty := Queue.Top = Queue.Free;
      end Dequeue;

      procedure Empty_Queue is
      begin
         Queue.Top := Index'First;
         Queue.Free := Index'First;
         Queue.Is_Empty := True;
      end Empty_Queue;

   end Protected_Queue;

end generic_protected_queue;
