require'util'
require'events'

local query = require'loft.queries'

local cosmo = require 'cosmo'

----------------------------------------------
-- Persistence Provider for the Loft Module
----------------------------------------------
--

module(..., package.seeall)

database_engine = require 'loft.database'

description = [[Generic Module for Database Behaviour]]

-- ######################################### --
-- # API
-- ######################################### --
--  All persistence providers must implement
--  this API to respond to the Loft engine
--  the 'base' provider will provide all of these
--  interfaces, and you can extended them
--  in your own providers
-----------------------------------------------

-- -------------- --
-- FUNCTIONS
-- -------------- --

-- setup(engine)

-- create(engine, entity)
-- persist(engine, entity, id, data)
-- retrieve(engine, entity, id)
-- delete(engine, entity, id)

-- search(engine, options)
-- count(engine, options)

-- -------------- --
-- BASE PROPERTIES
-- -------------- --
-- Providers that use SQL and extend Base can make use of
-- these properties to extend behavior without rewritting
-- the API functions

-- database_engine

-- quotes
-- filters.like
-- filters.contains
-- escapes.quotes
-- escapes.new_lines
-- escapes.reserved_field_name

-- database_type
-- reserved_words
-- field_types
-- sql


-- ######################################### --
--  OPTIONS
-- ######################################### --
--  this provider default options


database_type = 'base'

reserved_words = util.indexed_table{}

reserved_words {
	'and',
	'fulltext',
	'table'
}

filters = {

	like = function(s)
		return string.gsub(s or '', '[*]', '%%')
	end,

	contains =function(f,s)
		return string.format("CONTAINS(%s, %s)", f, s)
	end,

}

quotes = [[']]

escapes = {
	quotes = function(s)
		return string.gsub(s or '', "'", "''")
	end,

	new_lines = function(s)
		return string.gsub(s or '', "\n", "\\n")
	end,

	reserved_field_name =function(s)
		return string.format('`%s`', s)
	end

}

local function contains_special_chars(s)
	return string.find(s, '([^a-zA-Z0-9_])')~=nil
end

escape_field_name=function(s)
	return (reserved_words[string.lower(s)] or contains_special_chars(s)) and escapes.reserved_field_name(s) or s
end

string_literal=function(s)
	return quotes .. escapes.quotes(escapes.new_lines(s)) .. quotes
end

field_types = {
	key={type='BIGINT', size='8', required=true, primary=true, autoincrement=true, onEscape=tonumber, onRetrieving=tonumber},
	integer={type='INT', size='5', onEscape=tonumber, onRetrieving=tonumber},
	number={type='DOUBLE', onEscape=tonumber, onRetrieving=tonumber},
	currency={type='DECIMAL', size={14,2}, onEscape=tonumber, onRetrieving=tonumber}, -- TODO: create a currency helper
	text={type='VARCHAR',size='255', onEscape=string_literal},
	long_text={type='LONGTEXT', onEscape=string_literal},
	timestamp={type='DATETIME'}, --TODO: create a datetime helper
	boolean={type='BOOLEAN'},

	has_one={type='BIGINT', size='8', onEscape=tonumber},
	belongs_to={type='BIGINT', size='8', onEscape=tonumber},
}

--  ]=]

sql = {

	CREATE = [==[
CREATE TABLE IF NOT EXISTS $table_name (
  $columns{","}[=[$escape_field_name{$column_name} $type$if{$size}[[($size)]]$if{$primary}[[ PRIMARY KEY]]$if{$required}[[ NOT NULL]]$if{$description}[[ COMMENT  $string_literal{$description}]]$if{$autoincrement}[[ AUTO_INCREMENT]]$sep
]=]);]==],

	INSERT = [[INSERT INTO $table_name ($data{", "}[=[$escape_field_name{$column_name}$sep]=]) VALUES ($data{", "}[=[$value$sep ]=])]],

	UPDATE = [==[UPDATE $table_name SET $data{", "}[=[$escape_field_name{$column_name}=$value$sep]=] $if{$filters}[=[WHERE ($filters_concat{" AND "}[[$it$sep]])]=]]==],

	SELECT = [===[SELECT
  $columns{","}[[ $if{$column_name}[[$escape_field_name{$column_name}]][[$func]] as $escape_field_name{$alias}$sep
  ]]FROM $table_name
  $if{$__joins}[==[$from_alias $__joins[=[$type JOIN $join_table $alias ON ( $on_clause ) ]=]
  ]==]$if{$filters}[=[WHERE ($filters_concat{" AND "}[[$it$sep]])]=] $if{$has_sorting}[=[ORDER BY $sorting_concat{", "}[[$it$sep]]]=] $if{$pagination}[=[$if{$pagination|limit}[[ LIMIT $pagination|limit ]] $if{$pagination|offset}[[OFFSET $pagination|offset]]]=]]===],

	DELETE = [==[DELETE FROM $table_name $if{$filters}[=[WHERE ($filters_concat{" AND "}[[$it$sep]])]=]]==],

	LASTID = [==[SELECT LAST_INSERT_ID()]==],

	GET_TABLES = [==[SHOW TABLES]==],

	GET_TABLE_DESCRIPTION = [==[DESCRIBE $table_name]==],

	IN = ' IN ',
	NOTIN = ' NOT IN ',
	IS = ' IS ',
	LIKE = ' LIKE ',
	EQ = ' = ',
	LT = ' < ',
	GT = ' > ',
	GE = ' >= ',
	ISNULL = ' IS NULL',
	ISNOTNULL = ' IS NOT NULL',

	set = function(items)
		local content = type(items)=='table' and table.concat(items, ', ') or tostring(items)
		return '('..content..')'
	end,

	field_name = function(query, field)
		if type(field)=='string' then
			return field
		else
			assert(field.column_name, "Invalid field on criteria")
			return (query.from_alias and (field.entity_name .. '.') or '') .. field.column_name
		end
	end,

	filters = function(query, filters)
		--TODO: add support for OR clauses and more complex conditions

		local _,result = query:conditions(filters or {})

		if next(result) then
			query.filters = {}
		end
		query.filters_concat = cosmo.make_concat( result )
	end,

	condition = function(query, lside, op, rside)
		return tostring(lside)..tostring(op)..tostring(rside)
	end,

	join_conditions = function(list)
		return table.concat(list, ' AND ')
	end
}

-- ######################################### --
--  INTERNALS
-- ######################################### --


local passover_function = function(...) return ... end


render_engine = {
	templates = sql,

	prepare = function(query, filters)
		query:renderer(render_engine)

		if ( not query.table_name and not query.name ) then
			error("Entity must have a  `name` or `table_name`.")
		end

		query.columns = cosmo.make_concat( query.__fields )

		query['string_literal'] = function (arg)
			return string_literal(arg[1])
		end

		query['escape_field_name'] = function (arg)
			return escape_field_name(arg[1])
		end

		query["if"] = function (arg)
		   if arg[1] then arg._template = 1 else arg._template = 2 end
		   cosmo.yield(arg)
		end

		if filters then
			render_engine.templates.filters(query, filters)
		end

		return query
	end,

	render = function(query, options)
		local options = options or {}
		local query_type = options.type or options[1] or 'SELECT'
		for name, data in pairs(options) do
			if not tonumber(name) then
				if type(data)=='table' then
					query[name] = cosmo.make_concat( data )
				else
					query[name] = data
				end
			end
		end

		return cosmo.fill(sql[query_type], query)
	end
}

function get_field_entity(f, entities)
	return entities[f.entity]
end

function find_field(engine, entity, field_name, fn)
	local fn = fn or get_field_entity;
	local provider = engine.provider or {};
	local entity = entity
	local field_path = {}
--print('field:', field_name)
	local relations, attr = util.split_field_name(field_name)
	for _,relation_name in ipairs(relations) do
--print('>', relation_name)
		local f = entity.fields[relation_name]

		if f and f.type then
			f.name = relation_name
			assert(f.entity, string.format("While looking for '%s': field '%s' must be a relationship", field_name,relation_name))
			entity = fn(f, engine.schema.entities)
			assert(entity, string.format("While looking for '%s': could not find entity '%s'", field_name,f.entity))

			table.insert(field_path, f)
		else
			print(string.format("While looking for '%s': relation '%s' must be present on entity '%s'", field_name, relation_name, entity and entity.name))
			return nil
		end
	end
	local field = table.merge({internal_name=attr, field_name=field_name}, entity.fields[attr])
	local field_type = table.copy(provider.field_types[field.type]) or {}

	return table.merge(field_type, field), entity, field_path
end

function integrate_foreign_field(prototype, row, field, field_path)
	local f = table.remove(field_path, 1)
	if f and (f.type=='belongs_to' or f.type=='has_one') then
		local prot = prototype[f.name] or {}
		integrate_foreign_field(prot, row, field, field_path)

		prototype[f.name] = prot
	--elseif f.type=='has_many' then
		-- TODO: add a proxy list to the entity filtered by the parent's id. That probably shouldn't be done here. Maybe a closure.
		--local prot = {}
	elseif field then
		local value = row[field.field_name]
		prototype[field.internal_name] = value
	end
end

function integrate_data_from_row(engine, entity, row)
	local entities = engine.schema and engine.schema.entities or {};
	local data = {}
	for key, value in pairs(row) do
	--TODO: treat all kinds of result
	-- 1. all fields from main entity [OK]
	-- 2. some from main entity, some are alien values or function results
	-- 3. some from main entity, some from a related entity, full load (has_one or belongs_to)
	-- 4. some from main entity, some form a related entity, early binding (has_one or belongs_to)
	-- 5. some from main entity, some form a related entity, some from a third related entity
	-- 6. some from main entity, some form a related entity, full load (has_many, has_and_belongs)
		local field, e, fs = find_field(engine, entity, key, get_field_entity)

		if field then
			local fn = field.onRetrieving or passover_function
			if #fs>0 then
				integrate_foreign_field(data, row, field, fs)
			else
				data[key] = fn(value)
			end
		end
	end
	return data
end

-- ######################################### --
--  PUBLIC API
-- ######################################### --

--- sets up specific configurations for this provider.
-- this function is executed when the engine is
-- created. It can be used primarily to create
-- the 'connection_string' or the 'connection_table' options from
-- a more human-readable set of options
-- @param engine the active Loft engine
-- @return alternative loft engine to be used or nil if the original engine is to be used
function setup(engine)
	engine.options.connection_table = {
		engine.options.database,
		engine.options.username,
		engine.options.password,
		engine.options.hostname,
		engine.options.port,
	}

	engine.db = database_engine.init(engine, engine.options.connection_table)

	engine.provider = _M

	return engine
end

--- stores an instace of an entity onto the database
-- if the entity has an id, generates an update statement
-- otherwise, generates an insert statement
-- @param engine the active Loft engine
function persist(engine, entity, id, obj)
	local query = query.create(engine, entity)
	obj.id = id or obj.id
	local data = {}
	local t_required = {}

	events.notify('before', 'persist', {engine=engine, entity=entity, id=id, obj=obj})

	-- Checking if every required field is present
	for i, column in ipairs(query.__columns) do

		if ( column.required ) then
			if ( not obj[ column.alias ] and column.alias ~= 'id') then
				table.insert( t_required, column.alias )
			end
		end

		if ( obj[ column.alias ] ) then
			local fn = column.onEscape or passoverFunction
			table.insert(data, {
				column_name = column.name,
				value = fn( obj[ column.alias ] )
			})
		end

	end

	if ( #t_required > 0 ) then
		error("The following required fields are absent (" .. table.concat(t_required, ',') .. ")")
	end

	local query_type = (obj.id) and 'UPDATE' or 'INSERT'

	local sql_str = query:render{ query_type, data=data, filters={ id=id } }

	--TODO: proper error handling
	--TODO: think about query logging strategies
	local ok, data = pcall(engine.db.exec, sql_str)

	if query_type=='UPDATE' then
		return ok, data
	end

	if ok then
		if data and type(data) == "table" then
			--TODO: refresh object with other eventual database-generated values
			obj.id = data.id or obj.id
		elseif not isUpdate and not obj.id then
			obj.id = engine.db.last_id()
		end

		events.notify('after', 'persist', {engine=engine, entity=entity, id=id, obj=obj, data=data })

		return true, obj.id
	else
		events.notify('error', 'persist', {engine=engine, entity=entity, id=id, obj=obj, message=data})

		return nil, data
	end
end

function create(engine, entity, do_not_execute)
	local query = query.create(engine, entity)

	local sql_str = query:render{ 'CREATE' }
	--TODO: proper error handling
	--TODO: think about query logging strategies

	return do_not_execute and sql_str or pcall(engine.db.exec, sql_str)
end

--- Eliminates a record  from the persistence that corresponds to the given id
-- @param engine the active Loft engine
-- @param entity the schema entity identifying the type of the object to remove
-- @param id identifier of the object to remove
-- @param obj the object itself
function delete(engine, entity, id, obj)
	local query = query.create(engine, entity)

	local sql_str = query:render{'DELETE', filters={ id=id } }

	--TODO: proper error handling
	--TODO: think about query logging strategies
	return pcall(engine.db.exec, sql_str)
end

-- retrieve(engine, entity, id)
--- Obtains a table from the persistence that
-- has the proper structure of an object of a given type
-- @param engine the active Loft engine
-- @param entity the schema entity identifying the type of the object to retrieve
-- @param id identifier of the object to load
-- @return object of the given type corresponding to Id or nil
function retrieve(engine, entity, id)
	local query = query.create(engine, entity)

	local sql_str = query:render{'SELECT', filters={ id=id } }

	--TODO: proper error handling
	--TODO: think about query logging strategies
	local ok, iter = pcall(engine.db.exec, sql_str)

	if ok then
		return iter()
	else
		return nil, iter
	end
end

-- search(engine, options)
--- Perform a visitor function on every record obtained in the persistence through a given set of filters
-- @param engine the active Loft engine
-- @param options the
-- 			entity the schema entity identifying the type of the object to retrieve
-- 			filters table containing a set of filter conditions
-- 			pagination table containing a pagination parameters
-- 			sorting table containing a sorting parameters
-- 			visitor	(optional) function to be executed
-- 					every time an item is found in persistence
--					if ommited, function will return a list with everything it found
-- @return 			array with every return value of the resultset, after treatment by the visitor
function search(engine, options)
	local entity, filters, pagination, sorting, visitorFunction =
 		(options.entity or options[1]), options.filters, options.pagination, options.sorting, options.visitor

	local query = query.create(engine, entity, options.include_fields, options.exclude_fields)

	if ( type(pagination) == "table" and table.count(pagination) > 0) then
		local limit = pagination.limit or pagination.top or options.page_size or engine.options.page_size
		local offset = pagination.offset or (pagination.page and limit * (pagination.page - 1))

		query.pagination = {limit=limit, offset=offset}
	end
	local sortingcolumns
	if ( type(sorting) == "table" and #sorting > 0 ) then
		sortingcolumns = {}
		for i, v in ipairs(sorting) do
			local d, f = util.op_field(v)
			if d=='-' then
				table.insert( sortingcolumns, escape_field_name(f)..' DESC')
			else
				table.insert( sortingcolumns, escape_field_name(f)..' ASC')
			end
		end

		query.has_sorting = {}
	end

	local sql_str = query:render{'SELECT', filters=filters, sorting_concat=sortingcolumns}

	--TODO: proper error handling
	--TODO: think about query logging strategies
	local ok, iter = pcall(engine.db.exec, sql_str)

	if ok then
		--TODO: implement resultset proxies using the list module
		--TODO: allow for many to many relationships without ID
		local results = {}
		local fn = visitorFunction or passover_function
		local row = iter()
		while row do
			local data = integrate_data_from_row(engine, entity, row)
			local o = fn(data)
			table.insert(results, o)
			row = iter()
		end
		return results
	else
		return nil, iter
	end
end

function get_tables(engine, options)
	local query = query.create()
	--TODO: proper error handling
	--TODO: think about query logging strategies
	local ok, iter = pcall(engine.db.exec, query:render{'GET_TABLES'})

	if ok then
		--TODO: implement resultset proxies using the list module
		local results = {}
		local row = iter()
		while row do
			local i, value = next(row)
			table.insert(results, value)
			row = iter()
		end
		return results
	else
		return nil, iter
	end
end

local function extract_type_in_description(type)
	if (string.find(type, "%(")) then --discovery size in type
		return string.match(type, "^([^(]-)%(([^)]-)%)")
	else
		return type
	end
end

function convert_description_in_table(row)
	local _type, size = extract_type_in_description(row.Type)
	local t = {}
	t.field = row.Field
	t.primary = (row.Key == "PRI") and true or nil
	t.required = (row.Null == "YES") and true or nil
	t.type = string.upper(_type)
	t.size = size or nil
	t.autoincrement = (row.Extra == "auto_increment") and true or nil
	return t
end

function get_description(engine, options)
	local table_name = options.table_name
	assert(table_name, "you need to inform a table name")

	local query = query.create()
	--TODO: proper error handling
	--TODO: think about query logging strategies
	local ok, iter = pcall(engine.db.exec, { 'GET_TABLE_DESCRIPTION', table_name = table_name })

	if ok then
		--TODO: implement resultset proxies using the list module
		local results = {}
		local row = iter()
		while row do
			table.insert(results, convert_description_in_table(row))
			row = iter()
		end
		return results
	else
		return nil, iter
	end
end
-- count(engine, options)
--- Gets the number of results of a given set of search options
-- @param engine the active Loft engine
-- @param options the
-- 			entity the schema entity identifying the type of the object to retrieve
-- 			filters table containing a set of filter conditions
-- @return 			number of results to be expected with these options

function count(engine, options)
 	local entity, filters, pagination, sorting, visitorFunction =
 		options.entity, options.filters, options.pagination, options.sorting, options.visitor

	local query = query.create(engine, entity)

	local sql_str = query:render{ 'SELECT', filters=filters, columns = { { func = 'COUNT(*)', alias = 'count' }} }

	local ok, iter_num = pcall(engine.db.exec, sql_str)

	if ok then
		--TODO: implement resultset proxies using the list module
		local results = {}
		local row = iter_num()
		if row then
			return row.count
		end
	end

	return nil
end

