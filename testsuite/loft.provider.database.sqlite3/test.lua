package.path = [[;;./net.luaforge.loft/source/lua/5.1/?.lua;./net.luaforge.loft/source/lua/5.1/?/init.lua;]]

local now = os.clock()
local log = function()
	print('log: ' .. os.clock() - now)
end

local provider = require"loft.providers.database.sqlite3"

local lfs = require'lfs'

provider.options{
	PERSISTENCE_FILENAME = 'test.db3';
	PERSISTENCE_PATH= './net.luaforge.loft/testsuite/'
}


local NUM_OF_OBJECTS_TO_GENERATE = 100

provider.initialize('test.db3')

-- generates an ID
local id = provider.getNextId('test')
local firstId = id
local times = {}

for i=1, NUM_OF_OBJECTS_TO_GENERATE do
	
	-- persists a given table
	provider.persist('test', id, {
		id=id; 
		name='test'..i; 
		address= (i*347) .. ', Elm Street';
	})
	-- counts how many times this particular ID has been generated
	times[id] = (times[id] and (times[id] + 1)) or 1
	id = provider.getNextId('test')
	
end
 
local generatedId = firstId
table.foreachi(times, function(k, v)
	assert(k == generatedId, 'generated Id is out of sequence') 
	assert(v == 1, 'generated Id is duplicated')
	generatedId = generatedId + 1
end)

local lastId = firstId + NUM_OF_OBJECTS_TO_GENERATE

assert(id==lastId, 'wrong number of objects created')

local t = provider.retrieve('test', lastId-1)
assert(t, 'object was not retrieved for id==' .. lastId)

assert(t.name == 'test' .. (lastId-firstId), 'The proper object was not retrieved')


local list = {}

provider.search('test', {name='test99'}, function(item)
	assert(item.name=='test99')
	table.insert(list, item)
end)

assert(#list==1, 'search did not find the item by name')

table.foreachi(list, function(i, item)
	provider.erase('test', item.id)
end)

list = provider.search('test', {name='test99'}, function(item)
	assert(item.name=='test99')
	table.insert(list, item)
end)

assert(#list==0, 'erase did not remove the item properly')


list = provider.search('test', {name='test98'})

assert(#list==1, 'short search did not find the item by name')

table.foreachi(list, function(i, item)
	provider.erase('test', item.id)
end)

list = provider.search('test', {name='test98'})

assert(#list==0, 'erase did not remove the item properly')

list = provider.search('test', {__sort='-name', __limit=10})

assert(#list==10, 'limited search has brought the wrong amount of items')

list = provider.search('test', {__sort='-name'})

assert(#list==98, 'global search found the wrong amount of items')

table.foreachi(list, function(i, item)
	provider.erase('test', item.id)
end)

list = provider.search('test', {})

assert(#list==0, 'erase did not remove all items properly')

print 'OK'