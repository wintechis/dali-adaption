/** 
* Name: CC 
* Contains centralized "VDA 5050-style" master that controls all AGVs (transporters)
* Author: Sebastian Schmid
*/ 


model failsafe_manufacturing
import "environment/Station_Item.gaml"

global {
	
	string setup_file<-""; 	//path to the file for the shop floor setup up
	string item_file<-""; 	//path to the file for the items list that shall be manufactured
	int no_transporter; //amount of transporters
	float world_width;	//width of world
	
	float anticipation_maximum <- 1.0;
	float anticipation_minimum <- 0.0;
	float anticipation_increase <- 0.002; 
	
	/*simulation parameters, used for different experiment setting */
	int disturbance_cycle <- 10000#cycles; //periodic cycle for distrubances. Is overwritten by parameter given in the experiment
	string master_status <- "on"; // functional status of the VDA master - on / off. Is overwritten by parameter given in the experiment.
	
	/*metrics*/
	list<float> residue <- [];

	float pre_mttd <- -1.0;
	int pre_outage_tdi <- -1;
	
	
	
	init{
		world_width <- shape.width ; //to calculate transporter speed s.t. they move exactly one grid square 
			
		file my_file <- text_file(setup_file); //get setup of shopfloor                 
        loop el over: my_file {
        	//entries have shape stationSpecies, station_type, cell_x, cell_y;
        	list tmp <- el split_with ',';        

			if(length(tmp) != 4)
			{
				error "Line misses entries!";
			}

			int x <- int(tmp[2]);
			int y <- int(tmp[3]);
			
			if(x >= width or y >= width or x < 0 or y < 0)
			{
				error "Coordinates for " + tmp[0]+"/" +tmp[1]+ " out of bounds (width = " + width + ")!";
			} 
        	
        	//check if cell has already been used by something else before (if a station / wall / whatever was already placed there, the status woulb be "obstacle=true" already!)
        	if(shop_floor[x,y].is_obstacle = false){
        		shop_floor[x,y].is_obstacle <- true; //in any case, transporters cannot drive through stations...
        	} else {//obstacle was already true! so there is a possible collision by using the same field twice!!
        		error "Shop floor tile at (" + x +", " +y+ ") seems to be already occupied by an obstacle!";
        	}
        	
        	switch tmp[0]{
        		match "work_station"{ //stations that transform items
        			create work_station {
        				station_type <- tmp[1];
        				do set_cell(shop_floor[x,y]); 
        			}					
        		}
        		match "periphery"{//fields that may not be accessed by transporters
        			create periphery {
        				do set_cell(shop_floor[x,y]);         				
        			}
        		}
        		match "source"{//stations that create items
        			create source {
        				do set_cell(shop_floor[x,y]); 
  				
        			}
        		}
        		match "shipping"{//stations that consume items
        			create shipping {
        				do set_cell(shop_floor[x,y]); 
        			}
        		}
        	}        	
        }
        
       	create transporter number:no_transporter returns: to_be_initalized;
       	ask to_be_initalized{
       		
       		do set_cell(one_of(shop_floor where (each.is_obstacle = false)));
       		
       		ini <- my_cell; //remember inital position
       	}
       
		create VDA5050master number:1;

	 	file item_list <- text_file(item_file); //import list of items and add to source 
		loop el over: item_list {
        	//list of stations to be visited by item 
        	list tmp <- el split_with ',';        
        	
        	ask source{
        		add tmp to: produce_item_list;
        	}
		}    	
	}
	
	
	reflex disturbances when: ((every(disturbance_cycle) and (cycle>0))){
	
		ask work_station{
			color <- #blue; //reset all stations to blue color
		}
		
		list<work_station> swappable <- copy_between(shuffle(work_station),0,2); //take two random work stations
		//swap stations descriptions 
		string buf <- swappable[0].station_type;
		swappable[0].station_type <- swappable[1].station_type;
		swappable[1].station_type <- buf;

		ask swappable{
			color <- #lightblue; //for visualization purposes s.t. it's easy to see what was swapped in the last cycle
		}
		
		ask transporter {
			cycles_since_triggered <- 0; //reset internal counters
			trigger_delay_measure <- true; //activate / reset measure reflex for delay
			
		}
	}
	


	
	//every "disturbance_cycles" cycles, we evluate the residue (aka the percentage of agents that do NOT know the truth)
	reflex evaluate_residue when: ((cycle > 1) and every(disturbance_cycle-1)){
		
		map<string, shop_floor> truth; //holds the objective truth of stations and their positions
		
		//add stations colot and position to the "truth"
		ask (agents_inside(shop_floor) of_generic_species station) {
			add (self.my_cell) at: self.station_type to: truth;	
		}
		
		float amt_suscpetible <- 0.0;
		
		ask transporter {
			if(self.MBA_model != truth){ //if agent model is not same as objective truth
				amt_suscpetible <- amt_suscpetible  +1;
			}
		}
		
		add (amt_suscpetible/float(no_transporter)) to: residue; //calculate residue
		
	}	
	
	//simulation ends automatically when all items were produced and consumed by shipping
	reflex end_sim when: (empty(source[0].produce_item_list) and empty(item)){
		
		do pause;
		
	}
	
	user_command "swap stations" action:swap; //user can swap stations manually by invoking action
	
	//same as reflex but for user command
	action swap{
		ask work_station{
			color <- #blue;
		}
		
		list<work_station> swappable <- copy_between(shuffle(work_station),0,2); //take two random work stations
		//swap stations descriptions 
		string buf <- swappable[0].station_type;
		swappable[0].station_type <- swappable[1].station_type;
		swappable[1].station_type <- buf;

		ask swappable{
			color <- #lightblue;
		}
	}
	
}
//########################################################################################################
//schedules agents, such that the simulation of their behaviour and the reflex evaluation is random and not always in the same order 
species scheduler schedules: shuffle(item+work_station+transporter);

//########################################VDA 5050 Master########################################
species VDA5050master{

	map<item,transporter> items_waiting; //dict of items that are transported transported atm (status=in_transit), associated with the transporter that shall pick them up
	map<item,transporter> items_in_transit; //dict of items that are transported transported atm (status=in_transit), associated with their transporter
	
	map<string, shop_floor> Master_model <- []; //model about positions of stations on the shop_floor. Entries have shape [rgb::location] 
	
	string status <- master_status; // functional status of the VDA master - on / off
	
	init {
		
		ask transporter{
			self.connected_to_master <- myself.status = "on" ? true : false;
		}
		location <- {world_width/2,0,15};
	}
	
	reflex perceive_floor when: (status = "on"){
		loop stat over: work_station {
			
			//Master knew about station before
			if(Master_model.keys contains stat.station_type){
			
				
				if((Master_model at stat.station_type) = stat.my_cell){
					//shop floor is still same position as before - do nothing
				}else{
					//position changed
				
					//recalculate >>delivering<< transporters. Not pick-up transporters, as they are coming for an ITEM, not for a station...
					//all transporters whose transported item wants to go to the changed station
					list<transporter> currently_delivering <- transporter where (items_in_transit.values contains each);
					
					if((currently_delivering!= nil) and (!empty(currently_delivering))){ //if there is something to reroute, do this...
					
						loop tr over: currently_delivering{
							//give new target position
							
							if((tr.storage) != nil and ( first(tr.storage.visit_stations) = stat.station_type ) ){
								tr.target <- stat.my_cell;
							}
						}
					}
					//update station's position
					add stat.my_cell at:stat.station_type to: Master_model;
				}
			} else {
				//if station was unknown, note down position
				add stat.my_cell at:stat.station_type to: Master_model;
			}
		}
	}

	//check if some order has been fulfilled by now, so Master can free the transporter
	reflex check_if_order_fulfilled when: ((status = "on") and !empty(items_in_transit) ){
		list<transporter> delivering_atm <- transporter where (each.status = "deliver");
		
		//all transporters that are currently in status "delivering"		
		loop tr over: delivering_atm{
		
			//when storage is empty, they are done with their delivery
			if( tr.storage = nil){
				remove key:first( items_in_transit.keys where ((items_in_transit at each) = tr) ) from: items_in_transit; //delete delivery request of these transporters
				tr.status <- "idle"; //reset transporter to idle
				
				//send back to inital position
				tr.target <- tr.ini;
			}
		}
	} 

	//as items could have been waiting, then disturbance, station changed, can now be processed, is processed, status then idle, VDA would try another transporter!
	reflex check_current_requests when: (status = "on"){
		
		loop it over: items_waiting.keys {
			//all these items should have status "waiting" - if they are suddenty idle, Master will cancel the contract and recalculate best pick below
			
			if(it.status = "idle"){ //idle can ONLY be, if a station has meanwhile transformed the item, e.g. by having a disturbance
				
				//reset transporter
				items_waiting[it].status <- "idle";
				items_waiting[it].target <- nil;
				
				//delete pickup up request
				remove key: it from: items_waiting;
			}
		}
	}
	
	//if there are idle items that still have to go somewhere and are not already being served, send a transporter
	reflex order_pickup_of_item when: ((status = "on") and !empty(item where ((each.status = "idle") and (!empty(each.visit_stations)) and !(items_waiting contains each)))) {
		
		list<item> unserved_items <- item where ((each.status = "idle") and (!empty(each.visit_stations)) and !(items_waiting contains each));
		
		loop it over: unserved_items{
			//get free transporters that are not currently used for pikcup or delivery
			list<transporter> idle_transp <- transporter where ((each.status = "idle") and !(items_waiting.values contains each) and !(items_in_transit contains each));
			
			//if transporter are available
			if(!empty(idle_transp))
			{
				transporter best_pick <- closest_to(idle_transp, it ); //take closest idle transporter 
				
				best_pick.status <- "pickup"; //now transporter is not idle anymore
				best_pick.target <- it.my_cell; //go to item position
				
				it.status <- "waiting";
				
				add best_pick at: it to: items_waiting; //write down that this transporter is currently used to pickup said item					
				
			}else{
				break; //items cannot be serverd atm
			}
		}
	}
	
	//item gets status in_transit after being picked up by a transporter
	reflex order_delivery_of_item when: ((status = "on") ){
		ask transporter{
			//get all transporters that are currently idle and carry an item	
			if((self.status = "idle") and (self.storage != nil)){
				//set target as nearest station for their carried item
				self.target <-  closest_to(((agents_inside(shop_floor) of_generic_species station) where (each.station_type = first(self.storage.visit_stations))), self.location ).my_cell;
				self.status <- "deliver"; 
			
				remove key:storage from: myself.items_waiting;
				add self at: storage to: myself.items_in_transit;
			}
		}
	}
	
	
	//+++++++++++++++++ user commands +++++++++++++++++
	user_command "disconnect master" action:disconnect ;
	user_command "reconnect master" action:reconnect;
	
	/*disconnect master from all transporters */
	action disconnect{
		
		ask transporter{
			self.connected_to_master <- false; //all transporters lose connection
		}
		
		status <- "off"; // set own status to OFF
		//do printStatus;
	}
	
	/*reconnect master to all transporters */
	action reconnect{
		ask transporter{
			self.connected_to_master <- true; //all transporters regain connection
		}
		status <- "on"; // set own status to ON
		
		/** hard reset of all transporters and items**/
		
		loop k over: items_in_transit.keys{//check if all pairings of items and transporters are still valid
			
			if(dead(k) = true){// if item was meanwhile delivered (== dead), remove pairing from list
				
				remove key: k from: items_in_transit;
				
			}
			
		}
		
		//reset transporter status
		/*status of delivering transporters will be "deliver" again, but targets are re-calculated and status respectively set.
		 * pickup and idle will be set to "idle", as master can decide about (possibly) better option who has to pickup what and which transporter goes where */
		ask transporter {
			self.status <- "idle"; //force status to idle (even if pickup or delivering)
			self.target <- nil; //reset target to nil
						
			if(self.storage != nil){//if transporter carries something
			
				self.storage.status <- "in_transit"; // set status of carried item to in_transit 
				
				//check where item should go, if shipping or work station
				if(first(self.storage.visit_stations) != "shipping"){
					self.target <- closest_to((work_station where (each.station_type = first(self.storage.visit_stations))), self.storage.location ).my_cell; //set new target w.r.t. to current status 
				}else{
					self.target <- closest_to(shipping, self.storage.location ).my_cell;
				}
				
				self.status <- "deliver"; //set transporter status to deliver
				add self at: self.storage to: myself.items_in_transit;
			}
		}
		
		//do printStatus;
	}
	
	action printStatus{
		write "" + cycle + " - " + name + " has status " + status;
	}
	
	aspect base3d {
		
		rgb col <- #grey;
		float size <- cell_width;
		
		if(status = "on"){
			col <- #yellow;
			size <- 4*cell_width;
		}
		
		draw pyramid(size) color: col border:#black; //yellow pyramid to symbolize an "all seeing eye" - grey if deactivated
	}
}

//########################################Transporter agents########################################


species transporter skills: [moving] parent:placeable  schedules:[]{
	
	rgb col <- #gray ;
	
	float speed <- world_width / width; //shape width is the width of the environment (defaul = 100), width the amount of cells in the grid
	shop_floor target<-nil;

	shop_floor ini <-nil; //initial positiion

	item storage <- nil;
	string status <- "idle"; //idle / pickup / deliver / explore
	
	bool connected_to_master;
	
	/*A station can be described by agent_model & a timestamp*/
	map<string, shop_floor> MBA_model <- []; //model about positions of already found or communicated stations. Entries have shape [string::location] 
	map<string, int> last_observed <- []; //note down which station has been observed WHEN for the last time 
	map<string, int> invalidated <- []; //note down which station has been invalidated when 
	
	map<string, float> anticipation <- []; //save current curiosity of the agent to visit the station again. [string::float]
	
	
	list<shop_floor> unexplored_tiles <- [];
	list<shop_floor> tiles_i_checked <- [];
	
	list<int> delays <- []; //delays until all knowledge was discovered
	
	init{
		
	}
	//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Display for humans %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	reflex HumanPerceptionStuff {
		
		switch status{
        		match "deliver"{
        			col <- #green; //delivering and knowing where to go
        		}
        		match "explore"{
        			if(storage = nil){
	        			col <- #orange; //exploring, but having nothing to deliver --> exploring for validity of its model
        			}else{
        				col <- #purple;//exploring, but having something to deliver --> exploring until discovery of its goal
        			}
        		}
        		match "idle"{
        			col <- #grey; //just wandering
        		}
        		match "pickup"{
        			col <- #brown;//on its way to pick something up, because it was nosy
        		}
        	}  
	}
	
	//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Perception %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	//if an agent has no entries at all, it is curious to get ANY entry at least
	reflex youngAndreckless when:((!connected_to_master) and (MBA_model.keys = []) and (status != "deliver") ){ 
			
			status <- "explore";
			target <- nil; //reset target to prevent first time use transporters to be captured in "explore" state with old target from master 
	}
	
	//add white tiles to the agents internal white_tiles list to remember white tiles were last seen (aka tiles that havent been directly visited yet)
	reflex perceiveUnexploredTiles when:(!connected_to_master and (status = "explore")){
		
		list<shop_floor> wt <- (my_cell neighbors_at 1 where (!(tiles_i_checked contains each) and (each.is_obstacle = false))); //get all valid (= not obstacle) tiles
		
		unexplored_tiles <- ((unexplored_tiles + wt)); //add them to list
				
		unexplored_tiles <- remove_duplicates(unexplored_tiles); //remove any accidental duplicates
		
		//check neighbors and own tile - if they were already visited, remove from white tiles list		
		loop t over: ((my_cell neighbors_at 1)+my_cell) {
			
			if((tiles_i_checked contains t) and (unexplored_tiles contains t)){
				
				remove t from: unexplored_tiles;
			}
		}
	}
	
	reflex perceiveNewStation when:(!empty(agents_inside(my_cell.neighbors) of_generic_species station)){
		
		station stat <- first(agents_inside(my_cell.neighbors) of_generic_species station);	
		if(!(MBA_model.keys contains stat.station_type)){ //if not already known 
			add stat.my_cell at: stat.station_type to: MBA_model; //save position of station
			add cycle at: stat.station_type to: last_observed; //save position of station
			add 0 at: stat.station_type to: invalidated; //save position of station
			
			add anticipation_minimum at:stat.station_type to: anticipation; //initalize with 0 as station has been perceived
			
		} else if(MBA_model.keys contains stat.station_type){ //agent knows about perceived station type 
			
			//invalidate all other stations that point to THIS currently perceived stations cell (as current observaton take precendence)
			
			//return all keys that point to the current cell and are NOT the currently perceived station
			list<string> old_entries <- (MBA_model.keys where (((MBA_model at each) = stat.my_cell) and ((invalidated at each) <= (last_observed at each))) ) - stat.station_type; 
			
			
			if(!empty(old_entries) and !connected_to_master and !(status="deliver" or status="pickup" )){
				
				//model was invalited, thus start exploration process
				status <- "explore";
			}
			
			loop old over:old_entries{
				add cycle at: old to: invalidated; //invalidate old station's entry
				
			}
			
			//update position of the current station in either way
			add stat.my_cell at: stat.station_type to: MBA_model; //update new position 				
			add cycle at: stat.station_type to: last_observed; //update observation cycle of station
		}			
	}

	//natural increase of curiosity, if stations are known and nothing is carried around
	reflex natural_increase when: (!empty(anticipation.keys) and storage = nil and status = "idle"){
		
		string stat <- one_of(anticipation.keys); //select random entry
		add (((anticipation at stat)  + anticipation_increase <= anticipation_maximum ? (anticipation at stat)  + anticipation_increase : anticipation_maximum)) at:stat to: anticipation; // increase by factor
	} 

	//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Communication %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
		
	reflex communicate_with_neighbors when: (!empty(agents_inside(my_cell.neighbors) of_species transporter)) {
			do AE1_PULL;
	}
	
	//actively check surroundings for ONE neighbor and PULL knowledge about observations
	action AE1_PULL {
		
		//transporter neighbor <-  one_of(agents_inside(my_cell.neighbors) of_species transporter); //returns one neighbor
		list<transporter> neighbor <-  agents_inside(my_cell.neighbors) of_species transporter; //returns one neighbor
		
		
		ask neighbor{
				
			loop stat over: self.MBA_model.keys {
	
				//didnt know about that one before! take it
				if(!(myself.MBA_model.keys contains stat)){
					add (self.MBA_model at stat) at:stat to: myself.MBA_model; //save station type and position
					add (self.last_observed at stat) at: stat to: myself.last_observed; //save position of station
					add (self.invalidated at stat) at: stat to: myself.invalidated; //save position of station
					
					add anticipation_minimum at:stat to: myself.anticipation; //create new OWN anticipation for agent
					
				} else { //knew about that one before
					
					//if neighbors OBSERVATION is more recent AND still valid w.r.t. agent knowledge, apply to own model
					if( ((self.last_observed at stat) >  (myself.last_observed at stat)) and ((self.last_observed at stat) > (myself.invalidated at stat)) ){
						add (self.MBA_model at stat) at:stat to: myself.MBA_model; //save station type and position
						add (self.last_observed at stat) at: stat to: myself.last_observed; //save position of station
						add (self.invalidated at stat) at: stat to: myself.invalidated; //save position of station
					}
					
					//if neighbors INVALIDATION is more recent AND still valid w.r.t. agent knowledge, apply to own model
					if( ((self.invalidated at stat) >  (myself.last_observed at stat)) and ((self.invalidated at stat) > (myself.invalidated at stat)) ){

						add (self.MBA_model at stat) at:stat to: myself.MBA_model; //save station type and position 
						add (self.last_observed at stat) at: stat to: myself.last_observed; //save position of station
						add (self.invalidated at stat) at: stat to: myself.invalidated; //save position of station
											
					}
				}
			}

			//if agent is exploring, ask neighbor for already explore tiles
			if(myself.status = "explore" and self.status = "explore" ){
				myself.tiles_i_checked <- myself.tiles_i_checked union self.tiles_i_checked;
				myself.unexplored_tiles <- myself.unexplored_tiles union self.unexplored_tiles;
				
				myself.unexplored_tiles <- myself.unexplored_tiles - myself.tiles_i_checked;
				
				/*compare target tiles - if your target is equal to or a neighbor of my target, i have to change my target*/
				if((myself.target != nil) and (self.target != nil) and ((self.target.neighbors + self.target) contains myself.target ) ){
					
					myself.target <- nil; //reset target
				}
			}
		}
	}
	
	reflex SanityCheckExploration when: status = "explore"{
		
		bool reset_status <- true;//prepare for check if model is consistent
		
		if(storage != nil){ //if something is carried around
			
			//if there is knowledge about the target
			if(MBA_model.keys contains first(storage.visit_stations)){
				
				string stat <- first(storage.visit_stations);
				
				//if this knowledge is NOT valid
				if((last_observed at stat) <= (invalidated at stat)){
					reset_status <- false; //do not reset, but look further for target
				}else{//if this knowledge is valid
					reset_status <- true; //reset status
				}
				
			} else{//if there is no knowledge about target
				reset_status <- false;//look further for target
			}
			
		}else if(!empty(MBA_model.keys)){//check if all model entries are currently correct aka cycle where last observed > invalidated
			loop stat over: last_observed.keys{

				//if so, reset to idle, as world seems to be correct
				if((last_observed at stat) <= (invalidated at stat)){
					reset_status <- false;
				}
			}
		
		}else{//we are curious by default... if nothing is known, we are going on an adventure
			reset_status <- false;
		}
		
		//reset status with respect to storage status
		if(reset_status){
					
			unexplored_tiles <- [];
			tiles_i_checked <- [];
			
			//if something was / is carried around, reset to deliver
			if(storage != nil){
				status <-"deliver";
			} else if (storage = nil){
				status <-"idle"; //if not, reset to idle
			}
			
		} else{
						
			tiles_i_checked <- remove_duplicates(tiles_i_checked);
			unexplored_tiles<- remove_duplicates(unexplored_tiles);
			unexplored_tiles <- unexplored_tiles where (each.is_obstacle = false);
	
			/*Sanity check if transporter meanwhile got to known that a current target is outdated */
			if(tiles_i_checked contains target){
				target <- nil; //obviously target was already checked so agent doesnt need to go there anymore...
				//a subsequent reflex will decide over a new target
			}
		}
	}
	
	//########################Exlporation########################
	user_command "mark known" action:mark_known_tiles ;
	user_command "reset known" action:reset_known_tiles;
	user_command "mark unknown" action:mark_unknown_tiles ;
	user_command "reset unknown" action:reset_unknown_tiles;

	action mark_known_tiles {		//for debugging purposes
		ask tiles_i_checked{
					color <- #yellow;
				}
			}
			
	action reset_known_tiles {		//for debugging purposes
	ask tiles_i_checked{
				color <- #white;
			}
		}
		
		action mark_unknown_tiles {		//for debugging purposes
		ask unexplored_tiles {
					color <- #pink;
				}
			}
			
	action reset_unknown_tiles {		//for debugging purposes
	ask unexplored_tiles{
				color <- #white;
			}
		}

	/*Frontiert based exploration: transporters save already explored (visited) tiles and note the adjacent, unvisited tiles as new options. Explored areas shall form a clustered area by using options with lots of already explored neighbors */
	reflex marked_explorative_wandering when: ((status = "explore") and (target = nil)){
		
		/********* Clustering by using neighbors with most bordering tiles*/
		unexplored_tiles <- unexplored_tiles where (each.is_obstacle = false); //to ensure only exploring accesible cells
		list<shop_floor> options <- my_cell.neighbors where (unexplored_tiles contains each); //get all neighboring cells that count as not explored as option
			
		list<shop_floor> valid_options <- [];
		int max_support <- -1;
		loop o over: options{
			
			list<shop_floor> support <- tiles_i_checked where (each.neighbors contains o);
			
			if(length(support) > max_support ){
				max_support <- length(support);
				valid_options <- []; //rest for new max
				valid_options <- valid_options + o; // an option is valid, if it borders an already checked tile
			}else if(length(support) = max_support ){
				valid_options <- valid_options + o; // add option as it is as good as all before
			}
		}		
		
		//if no valid options exist, take closest unexplored tile in general
		if(empty(valid_options))
		{
			valid_options <- list(closest_to((unexplored_tiles where (each.is_obstacle = false)), my_cell));
		}
		
		//if that was also empty... just go to any valid neighbor...
		if(empty(valid_options))
		{
			valid_options <- my_cell.neighbors where (each.is_obstacle = false); //get
		}
		
		
		target <- one_of((valid_options where (each.is_obstacle = false)));
		
	}

	//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Measure Delay %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	
	bool trigger_delay_measure <- false; //initalized with false to wait for first disturbance
	int cycles_since_triggered <- 0;
	
	//this reflex is only for measurement of delay - the transporter does not use the global knowledge used in here
	reflex delayMeasure when: (trigger_delay_measure) { 
		
		if(length(MBA_model.keys) = length(source+shipping+work_station)){
			//if model misses information about presence of an existing station on the shop floor, the model is not complete...
					
			bool all_right <- true;
			
			loop stat over: (source+shipping+work_station) {
				//(station where (each.station_type=k))
				
				if(shop_floor(stat.location) != (MBA_model at stat.station_type)){
					//knowledge point not to same location as truth 
					all_right <- false;
					break;
				}
			}
			
			if(all_right = true){
				add cycles_since_triggered to:delays;
				trigger_delay_measure <- false; //don't measure delay anymore (for this disturbance cycle)
			}
		}

		cycles_since_triggered <- cycles_since_triggered+1; //increase passed cycles
		
	}
	
	//%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% Interaction %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%	
	/*Order was to go somewhere and pick an item up */
	reflex pickupOrder when:((connected_to_master) and (storage=nil) and status="pickup" and (shop_floor(location) in (target neighbors_at 1))){
		
		station stat <-  first((agents_inside(my_cell.neighbors) of_species source + agents_inside(my_cell.neighbors) of_species work_station)); //gets all available stations nearby

		storage <- stat.storage;
		stat.storage <- nil;
		
		storage.status <- "in_transit";
		storage.my_cell <- my_cell;
		storage.location <- my_cell.location;
		
		status <- "idle";
		target <- nil;
	}
	
	/*When transporter perceived a station with an item AND is not currently on its was to check some other station*/
	reflex pickup when: ((!connected_to_master) and (status!="pickup") and (storage=nil) and !empty(agents_inside(my_cell.neighbors) of_generic_species station)){  
		
		station stat <-  first(agents_inside(my_cell.neighbors) of_generic_species station);//gets all available stations nearby
		
		//there's a product to pick up and it has to go somewhere else
		if((stat.storage != nil) and (first(stat.storage.visit_stations) != stat.station_type)){ 
			storage <- stat.storage;
			stat.storage <- nil;
		
			storage.status <- "in_transit";
			storage.my_cell <- my_cell;
			storage.location <- my_cell.location;
			
			status <- "deliver"; //set transporter's status to "deliver" as it will carry an item to its destination
			
		} else {
			//nothing because there's is nothing of interest for this transporter				
		}
		
		add anticipation_minimum at:stat.station_type to: anticipation; //reset as curiosity has been fulfilled
	}

	//if something is carried around, check knowledge	
	//if transporter does not know where to go (target = nil), check model (also in succesive steps as agent could've learned about target meanwhile)
	reflex checkModelEntries when: ((!connected_to_master) and (status!="explore") and (storage !=nil)) {
				
		if(contains_key(MBA_model, first(storage.visit_stations))){ //if we know about target				
			
			//if it is still valid
			if((invalidated at first(storage.visit_stations)) <  (self.last_observed at first(storage.visit_stations))){
				target <- MBA_model at first(storage.visit_stations) ;
			}else{
				//if not, reset target to nil and switch to exploration. another reflex will handle exploration
				target <- nil;
				status <- "explore";
			}
			
		} else {
			
			//the current target is unknown as it was not discovered yet
			target <- nil; //reset target anyway, especially for the case that transporter has an old target from the master (as it cannot be sure the target is still valid, reset)
			status <- "explore";
			
		}
		//else nothing is done - if no knowledge exists, no target is set. another reflex will handle wandering then
	}

	/*Order was to go somewhere and deliver whatever is in your storage*/
	reflex deliverOrder when:((connected_to_master) and (storage!=nil) and status="deliver" and (shop_floor(location) in (target neighbors_at 1))){
		
		station stat <-  first((agents_inside(my_cell.neighbors) of_species shipping + agents_inside(my_cell.neighbors) of_species work_station)); //gets
		if(stat.storage = nil) //if there's space, else wait...
		{
			storage.my_cell <- stat.my_cell;
			storage.location <- stat.my_cell.location;
			stat.storage <- storage;
			storage <- nil;
			
			storage.status <- "delivered";
			
			target <- nil;
		} else{
			//do nothing	
		}
		
	}	

	/*Order was to go somewhere and deliver whatever is in your storage*/
	reflex deliver when:(!(connected_to_master) and (storage!=nil) and !empty(agents_inside(my_cell.neighbors) of_generic_species station)){  
		//transporter carries something to deliver
		station stat <- first(agents_inside(my_cell.neighbors) of_generic_species station);
		
		if((stat != nil) and (stat.storage = nil)){
			if(stat.station_type = first(storage.visit_stations)){	
					
					storage.my_cell <- stat.my_cell;
					storage.location <- stat.my_cell.location;
					storage.status <- "delivered";
					
					stat.storage <- storage;
					storage <- nil;
					target <- nil;
					status <- "idle"; //reset transporters status
					
			} else{
				//do nothing
			}
		}	
	}
	
	reflex curiosity_wandering when: (!(connected_to_master) and (target = nil) and (status != "explore")) {
		
		//If transporter is empty, flip coin over one random entry to choose as "curious" target
		if(storage = nil){
	
			string stat <- one_of(anticipation.keys where ((invalidated at each) < (last_observed at each))); //equal probability for ALL VALID stations
			
			if(flip(anticipation at stat) = true){
				target <- MBA_model at stat;
				
				status <- "pickup"; //set status to commit to going to target (and not picking uo anything else earlier...)   
			}
		}
			
	}
	
	//If transporter got a target (either from VDA or retrieved from own knowledge), it moves to this goal
	reflex moveToTarget when: target != nil{
		
		if(status != "explore"){
		
			
			if((connected_to_master) and (status = "idle")){
				//movement to positions on the shop floor that have to be reached exactly, e.g. for return to initial position
				do goto on:(shop_floor where not each.is_obstacle) target:target  speed:speed return_path:true recompute_path: false;
				
			} else {

				//regular movement to things that are obstacles (e.g. work stations) -> move NEXT TO obstacle 
				do goto on:(shop_floor where not each.is_obstacle) target:closest_to((target neighbors_at 1 where not each.is_obstacle), my_cell)  speed:speed return_path:true recompute_path: false;
			}
			
			//update cell with new location
			do takeStep(location);
			
			//if transporter is at destination, target is fulfilled 
			if((!connected_to_master) and (status != "explore") and (my_cell in (target neighbors_at 1))){
				target <- nil;
				status <- "idle"; //reset status as target is reached
			} else if((connected_to_master) and (status = "idle") and (my_cell = target )){ //if transporter is ordered by master to go to a specific cell on the shop floor
				target <- nil; //reset status as target is reached
				//no status reset necessary as transporter is already "idle"
			}
			
		
		}else if(status = "explore"){
				
			do goto on:(shop_floor where not each.is_obstacle) target:target  speed:speed return_path:true recompute_path: false;
				
			//update cell with new location
			do takeStep(location);

			if(!(tiles_i_checked contains my_cell)){ // if my cell was NOT checked before
				tiles_i_checked <- tiles_i_checked + my_cell; //add this tile to the other checked tiles
			}
			
			//if target is reached, set target to nil
			if(my_cell = target){
				target <- nil;
			}
		}
	}
	
	//#########################################################################################
	reflex updateItem when: (storage != nil){
		storage.my_cell <- my_cell;
		storage.location <- my_cell.location;
	}
	
	action takeStep(point loc){
		my_cell <- shop_floor(loc);
		location <- my_cell.location;
	}
	
	aspect base{
		draw circle(cell_width) color: col border:#grey;
		
		//small yellow triangle appears ("all seeing eye")
		if(connected_to_master){
			draw triangle(cell_width/2) at: location + {cell_width*0.9,-cell_width*0.9} color: #yellow border:#black; //cell_width
			//draw circle(cell_width/8) at: location + {cell_width*0.9,-cell_width*0.9} color: #white border:#black;
			draw ellipse(cell_width/4, cell_width/8) at: location + {cell_width*0.9,-cell_width*0.9} color: #white border:#black;
			draw circle(cell_width/24) at: location + {cell_width*0.9,-cell_width*0.9} color: #black border:#black;  
		}		
	}
	
	aspect showName{
		draw string(name) color: #red ;
	}
	//draws arrow to show current target station 
	aspect fromTo{ 
		if(target != nil)
    	{draw line([location,target]) color: #red end_arrow: 2 empty: true;}  
	}
	
	aspect base3d{
		draw cylinder(cell_width,cell_width) color: col border:#grey;
	}
}

//########################################################################################################
experiment Fail_Safe_ShopFloor type:gui{
	parameter var: width<-25; //25, 50, 100	
	parameter var: cell_width<- 2.0; //2.0, 1.0 , 0.5
	parameter var:no_transporter<- 12;
	
	parameter var:setup_file<-"../includes/setup_smartphone.csv";
	parameter var:item_file<-"../includes/orderedItems100.csv";
	
	/*Three modes for triggering outages */
	//Mode 0: centralized mode, perfect behavior
	parameter var:master_status<- "on"; //initial status of the central control | for perfect centralized behavior, set trigger_outage = false, outage_after_first_delivery = false, AND only_outage_no_disturbance = false 
		
	//Mode 1: automatically after t_d including disturbances
	parameter var:disturbance_cycle <-100#cycles;


	output {	
		layout #split;
	 	display "Shop floor display" { 
			grid shop_floor lines: #black;
			species shop_floor aspect:base;
			species transporter aspect: base; 
			species transporter aspect:showName;
			species transporter aspect: fromTo;
			
			species work_station aspect: base;
			species source aspect: base;
			species shipping aspect: base;
			species item aspect: cool;
			//species item aspect: show_steps;
			species item aspect: show_next_station;
			species periphery aspect: cool;
			
		}
	}
}

experiment Fail_Safe_ShopFloor_3D type:gui{
	parameter var: width<-25; //25, 50, 100	
	parameter var: cell_width<- 2.0; //2.0, 1.0 , 0.5
	parameter var:no_transporter<- 12;
	
	parameter var:setup_file<-"../includes/setup_smartphone.csv";
	parameter var:item_file<-"../includes/orderedItems50.csv";
	
	
	parameter var:disturbance_cycle <-250#cycles;
	parameter var:master_status<- "on";
	
	output {	
		layout #split;
	 	display "Shop floor display" type: opengl{ 
			//camera name:#default locked: false location: #from_up_front distance: 200;
			
			grid shop_floor lines: #black;
			species shop_floor aspect:base;
			species transporter aspect: base3d; 
			species transporter aspect: fromTo;
			
			species work_station aspect: cool3d;
			species source aspect: cool3d;
			species shipping aspect: cool3d;
			species item aspect: cool3d;//base3d;
			species periphery aspect: base3d;
			
			species VDA5050master aspect: base3d;
		}
	}
}

/*###########################################################*/
/*Runs an amount of simulations in parallel, varies the the disturbance cycles*/ 
experiment Performance_centralised_no_outage type: batch until: ((empty(item)) and (cycle > 0) ) repeat: 12 autorun: true keep_seed: true{ 

	parameter var: width<-25; //25, 50
	parameter var: cell_width<- 2.0; //2.0, 1.0
	parameter "No. of transporters" category: "Transporter" var: no_transporter<-12 ; // 12

	parameter var:setup_file among: ["../includes/setup_smartphone2.csv"];//, "../includes/setup_smartphone2.csv"];
	parameter var:item_file among: ["../includes/orderedItems50.csv","../includes/orderedItems100.csv","../includes/orderedItems250.csv"];
	
	parameter var:disturbance_cycle among: [100#cycles,150#cycles,200#cycles,250#cycles,300#cycles,20000#cycles];
	parameter var:master_status among:  ["on"];

	reflex save_results_explo {
    ask simulations {
    	float mean_cyc_to_deliver <- mean(self.delivery_diffs);
    	int tdi <- self.shipping[0].delivered_items ; 
    	save [int(self), self.no_transporter, self.disturbance_cycle, tdi, self.cycle, mean_cyc_to_deliver, mean(self.residue), self.setup_file, self.item_file]
           to: "simulation_results/centralized/Sc2_CC_performance.csv" type: "csv" rewrite: false header: true; 
    	}       
	}		
}


/*###########################################################*/

