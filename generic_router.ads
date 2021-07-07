--
--  Framework: Uwe R. Zimmer, Australia, 2015
--

with Generic_Message_Structures;
with Generic_Router_Links;
with Id_Dispenser;

generic

   with package Message_Structures is new Generic_Message_Structures (<>);

package Generic_Router is

   use Message_Structures;
   use Routers_Configuration;

   package Router_Id_Generator is new Id_Dispenser (Element => Router_Range);
   use Router_Id_Generator;

   type Router_Task;
   type Router_Task_P is access all Router_Task;

   package Router_Link is new Generic_Router_Links (Router_Range, Router_Task_P, null);
   use Router_Link;
   -- the maximum length of the path is 100
   type Path_Index is new Positive range 1 .. 100;
   -- store the information of the routers in the path
   type Path_Array is array (Path_Index) of Router_Range;

   type Path_type is record
      Top, Free : Path_Index := Path_Index'First;
      Path      : Path_Array;
      Is_empty  : Boolean    := True;
   end record;

   function Empty      (path : Path_type) return Boolean;

   function Get_size   (path : Path_type) return Natural;

   function Find_Last  (path : Path_type) return Router_Range;

   procedure AddToPath (router : Router_Range;     path_queue : in out Path_type);

   procedure DeleteOne (router : out Router_Range; path_queue : in out Path_type);

   task type Router_Task (Task_Id  : Router_Range := Draw_Id) is

      entry Configure (Links : Ids_To_Links);

      entry Send_Message    (Message_sent :     Messages_Client);
      entry Receive_Message (Message      : out Messages_Mailbox);

      entry Shutdown;

      -- Leave anything above this line as it will be used by the testing framework
      -- to communicate with your router.

      -- use the path to update the table
      entry Update_table_message   (path : Path_type; origin : Router_Range);
      -- routers will using this entry to communicate with each other
      entry Exchange_Inner_Message (Message_inner : Messages_Inner);

      -- entry receive_Create_table_Message (Message :     Messages_Create_Table);
      --  Add one or multiple further entries for inter-router communications here.

   end Router_Task;

end Generic_Router;
