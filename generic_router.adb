--
--  Framework: Uwe R. Zimmer, Australia, 2019
--  The default maximun number of Routers is 100, if you want to change, please go to the generic_Router.ads and change the "Path_Index" to a specific number but not too large because it
--  it will raise stack overflaw error.

with Exceptions; use Exceptions;
with generic_protected_queue;

package body Generic_Router is

   function Empty (path : Path_type) return Boolean is
     (path.Is_empty);

   function Get_size (path : Path_type) return Natural is
     (Natural (path.Free - path.Top));

   function Find_Last (path : Path_type) return Router_Range is
      (path.Path (path.Free - 1));

   procedure AddToPath (router : Router_Range;     path_queue : in out Path_type) is
   begin
      path_queue.Path (path_queue.Free) := router;
      path_queue.Free                   := path_queue.Free + 1;
      path_queue.Is_empty               := False;
   end AddToPath;

   procedure DeleteOne (router : out Router_Range; path_queue : in out Path_type)  is
   begin
      router := path_queue.Path (path_queue.Top);
      path_queue.Top := path_queue.Top + 1;
      path_queue.Is_empty := path_queue.Top = path_queue.Free;
   end DeleteOne;

   task body Router_Task is

      Connected_Routers : Ids_To_Links;

      -- the buffer for message
      type index is mod 500;

      package Mailbox_messasge_queue is
        new generic_protected_queue (Element => Messages_Mailbox,
                                     Index   => index);
      -- messages arrvived at the destination and waiting for the client to pick up
      Mailbox_Queue : Mailbox_messasge_queue.Protected_Queue;

      package inner_message_queue is
        new generic_protected_queue (Element => Messages_Inner,
                                     Index   => index);
      -- inner messages waiting to be handled
      inner_Queue : inner_message_queue.Protected_Queue;

      MAX_INT : constant Natural := Natural'Last;
      type Connected_ports_type is array (Router_Range) of Router_Range;
      type Distance_table       is array (Router_Range) of Natural;

      -- this table store the connected router which will be passed in order to arrive at a specific router
      Destination_Connected_Port_list : Connected_ports_type := (others => Task_Id);
      -- Distance-Vector table stores the closest distance to a specific router
      RoutingTable                    : Distance_table       := (others => MAX_INT);

      Is_shutdown : Boolean := False;

   begin
      accept Configure (Links : Ids_To_Links) do
         Connected_Routers := Links;
      end Configure;

      declare
         Port_List : constant Connected_Router_Ports := To_Router_Ports (Task_Id, Connected_Routers);

         type Path_information is record
            Path   : Path_type;
            Origin : Router_Range;
         end record;

         package Node_information_queue is
           new generic_protected_queue (Element => Path_information,
                                        Index   => index);
         -- store all the paths that origin is other router
         Path_info_Queue : Node_information_queue.Protected_Queue;

         -- deal with all the received inner messages to decide whether forward this or keep it
         task inner_Message_sender;
         -- send the own path to other, or handle other path and to decide whether forward it or ignore it
         task Spread_And_Forward_Nodes is
            entry Initialization_Finished;
         end Spread_And_Forward_Nodes;

         empty_path : Path_type;

         task body Spread_And_Forward_Nodes is
         begin
            declare
               path_info       : Path_information;

               origin_router   : Router_Range;
               Path_List       : Path_type;
               Path_Length     : Natural;

               extend_path     : Boolean := False;
            begin

               accept Initialization_Finished;

               for port of Port_List loop
                  port.Link.all.Update_table_message (empty_path, Task_Id);
               end loop;

               empty_path.Top := 1; empty_path.Free := 1;

               while not Is_shutdown loop
                  Path_info_Queue.Dequeue (path_info);

                  origin_router := path_info.Origin;
                  Path_List     := path_info.Path;
                  Path_Length   := Get_size (Path_List);
                  -- it means we receive the path from the router that is connected with us
                  if Path_List.Is_empty or else Get_size (Path_List) = 0 then
                     RoutingTable (origin_router)                    := 1;
                     Destination_Connected_Port_list (origin_router) := origin_router;
                     AddToPath (router     => Task_Id,
                                path_queue => Path_List);
                     extend_path := True;
                  -- Dijkstra algorith to calculate the path
                  elsif RoutingTable (origin_router) > Path_Length + 1 then
                     RoutingTable (origin_router)                    := Path_Length + 1;
                     Destination_Connected_Port_list (origin_router) := Find_Last (Path_List);
                     AddToPath (router     => Task_Id,
                                path_queue => Path_List);
                     extend_path := True;
                  else
                     -- ignore it when path is too long
                     extend_path := False;
                  end if;
                  -- if we update the table then we should forward it
                  if extend_path then
                     extend_path := False;
                     for port of Port_List loop
                        port.Link.all.Update_table_message (Path_List, origin_router);
                     end loop;
                  end if;
               end loop;

            end;
         exception
            when Exception_Id : others => Show_Exception (Exception_Id);
         end Spread_And_Forward_Nodes;

         task body inner_Message_sender is
            inner_m   : Messages_Inner;
            Mailbox_m : Messages_Mailbox;
         begin
            while not Is_shutdown loop
               if not inner_Queue.Is_empty then

                  inner_Queue.Dequeue (inner_m);
                  -- message is received
                  if inner_m.receiver = Task_Id then
                     Mailbox_m.Sender      := inner_m.sender;
                     Mailbox_m.The_Message := inner_m.The_Message;
                     Mailbox_m.Hop_Counter := inner_m.Hop_inner;

                     Mailbox_Queue.Enqueue (Mailbox_m);
                  -- Router have not found the shortest path, so return to queue
                  elsif RoutingTable (inner_m.receiver) = MAX_INT then

                     inner_Queue.Enqueue (inner_m);
                  -- Router  found the shortest path, so send it
                  else
                     inner_m.Hop_inner := inner_m.Hop_inner + 1;
                     for port of Port_List loop
                        if port.Id = Destination_Connected_Port_list (inner_m.receiver) then
                           select
                              port.Link.all.Exchange_Inner_Message (inner_m);
                           or
                              delay 0.0005;
                              inner_m.Hop_inner := inner_m.Hop_inner - 1;
                              inner_Queue.Enqueue (inner_m);
                           end select;
                           exit;
                        end if;
                     end loop;
                  end if;

               end if;
            end loop;
         exception
            when Exception_Id : others => Show_Exception (Exception_Id);
         end inner_Message_sender;

      begin
         -- initialization
         RoutingTable (Task_Id) := 0;
         Spread_And_Forward_Nodes.Initialization_Finished;

         loop
            select
               -- receive path and put it in queue and wait for the task to deal with it
               accept Update_table_message (path : Path_type; origin : Router_Range) do
                  declare
                     path_info : Path_information;
                  begin
                     path_info.Path   := path;
                     path_info.Origin := origin;

                     Path_info_Queue.Enqueue (path_info);
                  end;
               end Update_table_message;

            or
               -- receive inner message decide which way it will go
               accept Exchange_Inner_Message (Message_inner : in Messages_Inner) do
                  declare
                     Mailbox_m : Messages_Mailbox;
                  begin
                     if Message_inner.receiver = Task_Id then
                        Mailbox_m.Sender      := Message_inner.sender;
                        Mailbox_m.The_Message := Message_inner.The_Message;
                        Mailbox_m.Hop_Counter := Message_inner.Hop_inner;
                        select
                           accept Receive_Message (Message : out Messages_Mailbox) do
                              Message := Mailbox_m;
                           end Receive_Message;
                        or
                           delay 0.0002;
                           Mailbox_Queue.Enqueue (Mailbox_m);
                        end select;

                     elsif RoutingTable (Message_inner.receiver) /= MAX_INT then

                        declare
                           update_inner_message : Messages_Inner := Message_inner;
                        begin
                           for port of Port_List loop
                              if port.Id = Destination_Connected_Port_list (update_inner_message.receiver) then
                                 update_inner_message.Hop_inner := update_inner_message.Hop_inner + 1;
                                 select
                                    port.Link.all.Exchange_Inner_Message (update_inner_message);
                                 else
                                    update_inner_message.Hop_inner := update_inner_message.Hop_inner - 1;
                                    inner_Queue.Enqueue (update_inner_message);
                                 end select;
                                 exit;
                              end if;
                           end loop;
                        end;

                     else

                        inner_Queue.Enqueue (Message_inner);

                     end if;
                  end;
               end Exchange_Inner_Message;

            or
               -- receive the client message put it in queue
               accept Send_Message (Message_sent : in Messages_Client) do
                  declare
                     inner_M   : Messages_Inner;
                     Mailbox_M : Messages_Mailbox;
                  begin
                     if Message_sent.Destination = Task_Id then
                        Mailbox_M.Sender      := Task_Id;
                        Mailbox_M.The_Message := Message_sent.The_Message;
                        Mailbox_M.Hop_Counter := 0;

                        select
                           accept Receive_Message (Message : out Messages_Mailbox) do
                              Message := Mailbox_M;
                           end Receive_Message;
                        else
                           Mailbox_Queue.Enqueue (Mailbox_M);
                        end select;

                        Mailbox_Queue.Enqueue (Mailbox_M);

                     else
                        inner_M.sender      := Task_Id;
                        inner_M.The_Message := Message_sent.The_Message;
                        inner_M.Hop_inner   := 0;
                        inner_M.receiver    := Message_sent.Destination;

                        for port of Port_List loop
                           if port.Id = Destination_Connected_Port_list (Message_sent.Destination) then
                              inner_M.Hop_inner := inner_M.Hop_inner + 1;
                              select
                                 port.Link.all.Exchange_Inner_Message (inner_M);
                              else
                                 inner_M.Hop_inner := inner_M.Hop_inner - 1;
                                 inner_Queue.Enqueue (inner_M);
                              end select;
                              exit;
                           end if;
                        end loop;

                     end if;
                  end;
               end Send_Message;

            or

               accept Shutdown;
               abort Spread_And_Forward_Nodes;
               abort inner_Message_sender;
               Is_shutdown := True;
               exit;

            or

               delay 0.00025;

            end select;

            select
               when not Mailbox_Queue.Is_empty =>
                  accept Receive_Message (Message : out Messages_Mailbox) do
                     Mailbox_Queue.Dequeue (Message);
                  end Receive_Message;
            or
               delay 0.00025;
            end select;

         end loop;
      end;

   exception
      when Exception_Id : others => Show_Exception (Exception_Id);
   end Router_Task;

end Generic_Router;
