/**
* Name: ShopFloor_Grid
* Author: Sebastian Schmid
* Description: defines superclass for all species as well as the shop floor   
* Tags: 
*/

model ShopFloor_Grid

global {
	
	
	float cell_width;
	int width; 
	
	init
	{
		
	}
}

species placeable schedules:[] {
	shop_floor my_cell <- one_of(shop_floor);
	
	init{
		location <- my_cell.location;	
	}
	
	action set_cell(shop_floor new_cell){
		
		my_cell <- new_cell;
		location <- my_cell.location;
	}
}

grid shop_floor width: width height: width neighbors: 8 use_individual_shapes: false use_regular_agents: false { 	
	bool is_obstacle <- false;
		
	
	map<shop_floor, int> edges <- [];    

	init{
		
		loop n over: (neighbors_with_distance(1)){
			
			add 0 at: n to: edges;
		}
		
		
	}

	list<shop_floor> neighbors_with_distance(int distance){
		//if distance is one, naturally i am only my own neighbor
		return (distance >= 1) ? self neighbors_at distance : (list<shop_floor>(self));
	} 
	
	list<shop_floor> von_neumann_neighbors{
		
		int x <- grid_x;
		int y <- grid_y;
		
		list<shop_floor> vn_neighbors <- [];
	
	
		/*perception */
		if((x+1 < width)){
			vn_neighbors <- vn_neighbors + (shop_floor grid_at {x+1, y});
		} 
		if(y-1 >= 0){
			vn_neighbors <- vn_neighbors + (shop_floor grid_at {x, y-1});
		} 
		if(x-1 >= 0){
			vn_neighbors <- vn_neighbors + (shop_floor grid_at {x-1, y});
		} 
		if(y+1 < width){
			vn_neighbors <- vn_neighbors + (shop_floor grid_at {x, y+1});
		}
		
		return vn_neighbors;
		
	} 
	
	
	 aspect info {
        draw string(name) size: 3 color: #grey;
        
    }
    
    aspect position {
        draw string(location) size: 0.5 color: #grey;   
    }
    
     aspect base {
        
    }
    
}

