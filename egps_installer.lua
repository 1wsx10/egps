url = "https://raw.githubusercontent.com/1wsx10/egps/master/egps.lua"
overwrite = true
data_directory = "/.egpsData/"
program_name = "egps"

function main()
	if not http then
		print("You need http to use this Installer")
		print("Set http_enable to true in ComputerCraft.cfg")
		return
	end

	local get_response = http.get(url)
	local egps_code = get_response.readAll()
	get_response.close()

	--startup file
	if not startup_has_egps() then
		local startup_file = fs.open("/startup", fs.exists("/startup") and "a" or "w")

		startup_file.writeLine("--load egps")
		startup_file.writeLine("if os.loadAPI(\"".. data_directory .. program_name .."\") then")
		startup_file.writeLine("	egps.loadAll()")
		startup_file.writeLine("	--uncomment these to start with them:")
		startup_file.writeLine("	--GPS:")
		startup_file.writeLine("	--egps.setLocationFromGPS()")
		startup_file.writeLine("end")

		startup_file.close()
	end

	--put the code
	if not fs.exists(data_directory) then
		fs.makeDir(data_directory)
	end

	if not fs.exists(data_directory .. program_name) or overwrite then
		egps_code_file = fs.open(data_directory .. program_name, "w")
		egps_code_file.write(egps_code)

		egps_code_file.close()
	end
end

function startup_has_egps()
	if not fs.exists("/startup") then
		return false;
	end

	local startup_file = fs.open("/startup", "r")
	local line = startup_file.readLine()
	while line do
		if string.match(line, "--load egps") then
			return true
		end
		line = startup_file.readLine()
	end
	startup_file.close()
	return false
end

main()
