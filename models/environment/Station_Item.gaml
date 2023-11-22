/**
* Name: Station_Item
* Author: Sebastian Schmid
* Description: defines items (entities that are transported) and stations (sources and destination for items)
* Tags: 
*/

model Station_item

import "ShopFloor_Grid.gaml"

global {
	
	image_file wall const: true <- file('images/wall.jpg');
	image_file metal const: true <- file('images/metal.png');
	image_file mtbo const: true <- file('images/mainboard.png');
	image_file smph const: true <- file('images/smartphone.png');
	
	list<float> delivery_diffs;
	
	init{					
	}


}


species item parent: placeable schedules:[]{
	list<string> visit_stations <- nil;
	
	rgb color <- #white;
	int cycle_created <- -1; //the cycle when this thing was created by a station
	int cycle_delivered <- -1; //the cycle when this thing was delivered to a accepting station via a transporter	

	string status <- ""; // idle / waiting / in_transit
	
	int total_steps_to_be_done;
	
	aspect base{
		
		draw circle(cell_width*0.6) color: color border:#black;
		draw string(length(visit_stations)) size: 10 color: #red;
	}
	
	aspect cool {
		
		if(first(visit_stations) = "shipping")//empty(visit_stations))
		{
			draw smph size: 2*cell_width empty: true;
		}else if (length(visit_stations) = 2){
			draw mtbo size: 2*cell_width empty: true;
		} else{
			draw metal size: 2*cell_width empty: true;
		}
	}
	
	aspect show_steps {
		draw ""+string(total_steps_to_be_done-length(visit_stations))+"/"+string(total_steps_to_be_done) size: 10 at: location+(cell_width) font: font('Default', 12, #bold) color: #darkgreen;
		
	}
	
	aspect show_next_station {
		draw ""+string(first(visit_stations)) size: 10 at: location+(cell_width) font: font('Default', 12, #bold) color: #darkgreen;
		
	}
	
	init{
		cycle_created <- cycle; //set the current cycle as "creation date" for this thing
		status <- "idle";
	}
	
	aspect base3d{
		
		draw cube(cell_width*0.6) at: location + {0,0,cell_width}  color: color border:#black;
		draw string(length(visit_stations)) size: 10 color: #red;
	}
	
	aspect cool3d {
		
		image_file txtre <- nil;
		
		if(first(visit_stations) = "shipping")//empty(visit_stations))
		{
			txtre <- smph ;
		}else if (length(visit_stations) = 2){
			txtre <- mtbo ;
		} else{
			txtre <- metal;
		}
		
		draw cube(cell_width*0.6) at: location + {0,0,cell_width}  border:#black texture: txtre;
	}
}

species station parent: placeable{
	string station_type <- "base"; //type of station
	item storage<- nil;
}

species source parent: station {
	
	string station_type <- "source"; //type of station
	item storage<- nil; //if nil, then this storage is empty
	rgb color <- #lightgreen;
	
	list<list<string>> produce_item_list;
	
	
	reflex create_item when: ((storage = nil) and !empty(produce_item_list)){  
		
		create item number: 1 returns: newItem;
		
		ask newItem{
			visit_stations <- first(myself.produce_item_list);
			remove first(myself.produce_item_list) from: myself.produce_item_list;
			do set_cell(myself.my_cell); 
			
			total_steps_to_be_done <- length(visit_stations);
		}
		
		storage <- newItem[0];//only 1 Item
		 
	}
	
	aspect base{
		draw square(2*cell_width) color: color border:#black;
		draw name size: 10 color: #red;
	}
	
	aspect base3d{
		draw cube(2*cell_width) color: color border:#black;
		draw name size: 10 color: #red;
	}
	
		aspect cool3d{
		draw obj_file('objects/palett.obj', 90::{-1,0,0}) size: cell_width*2 at: location + {0,0,0.25} rotate: 90 color: color border:#black  ;//, 90::{-1,0,0} rotate: 90 at: location + {0,0,7}
		draw name size: 10 color: #red;  
	}
	
	
}

species shipping parent: station {
	
	string station_type <- "shipping"; //type of station
	rgb color <- #lightgreen;
	item storage<- nil;
	int delivered_items <- 0;
	
	bool first_item_delivered <- false;
	
	reflex ship_to_destination when: (storage != nil){  
		
		ask storage{
			cycle_delivered <- cycle;

			/* calculation for MTTD */
			delivery_diffs <- delivery_diffs + (cycle_delivered - cycle_created);
			
			do die; 
		}
		storage <- nil;
		delivered_items <- delivered_items + 1; //increase counter
		
		if(delivered_items = 1){
			first_item_delivered <- true;
		}
				 
	}
	
	aspect base{
		draw square(2*cell_width) color: color border:#black;
		draw name size: 10 color: #red;
	}
	
	aspect base3d{
		draw cube(2*cell_width) color: color border:#black;
		draw name size: 10 color: #red;
	}
	
	
	aspect cool3d{
		draw obj_file('objects/palett.obj', 90::{-1,0,0}) size: cell_width*2 at: location + {0,0,0.25} rotate: 90 color: color border:#black  ;//, 90::{-1,0,0} rotate: 90 at: location + {0,0,7}
		draw name size: 10 color: #red;  
	}
	
	
}

species work_station parent: station schedules:[]{
	
	item storage<- nil; //if nil, then this storage is empty
	string station_type <- "base"; //type of station
	rgb color <- #blue;
	
	list<item> work_queue <- [];
	int current_step <- 0;
	int work_duration <- 0;//3;
		
	//if station can do work with this item
	reflex transform_item when: ((storage != nil)){   
		
		//if the item in station's storage can be processed, do so		
		if(station_type in storage.visit_stations){
			if(work_duration = current_step){//check if there is still work to do
			
				ask storage {
				//as work of station is done at the moment, remove from list
				remove myself.station_type from: visit_stations; 	
				status <- "idle";	
				}
				
				current_step <- 0 ; //reset progress
			}else{
				current_step<- current_step +1; //progress to next step
			}	
		} else if(storage.status = "in_transit"){
			//if station got an item that cannot be processed (either by disturbance or error), reset item state to idle s.t. system or transporters can remove it 
			ask storage {
				status <- "idle";	
			}
		}
		
		
		
	}
	
	aspect base{
		draw square(2*cell_width) color: color border:#black;
		draw station_type + replace(name, "work_station", " ") size: 10 at: location-(cell_width) color: #red;
	}
	
	aspect base3d{
		draw cube(2*cell_width) color: color border:#black ;
		draw station_type + replace(name, "work_station", " ") size: 10 at: location-(cell_width) color: #red;
	}
	
	aspect cool3d{
		draw obj_file('objects/workstation.obj', 90::{-1,0,0}) size: cell_width*0.7 at: location + {0,0,2} rotate: 90 color: color border:#black ;//, 90::{-1,0,0} rotate: 90 at: location + {0,0,7}  
		draw station_type + replace(name, "work_station", " ") size: 10 at: location-(cell_width) color: #red;
	}
	
}


species periphery parent: placeable{
	
	aspect base {
		draw square(2*cell_width) color: #black border:#black;
	}
	
	aspect cool {
		draw wall size: 2*cell_width empty: true;
	}
	
	aspect base3d {
		draw cube(2*cell_width) border:#black texture: wall ; //color: #black 
	}
	
}

