#!/usr/bin/env wsapi

require "orbit"
require "markdown"
cosmo = require "template.cosmo"

module("toycms", package.seeall, orbit.new)

require "toycms_config"
require "toycms_plugins"
require "toycms_admin"

require("luasql." .. database.driver)
local env = luasql[database.driver]()
mapper.conn = env:connect(unpack(database.conn_data))
mapper.driver = database.driver

models = {
   post = toycms:model "post",
   comment = toycms:model "comment",
   section = toycms:model "section",
   user = toycms:model "user"
}

function models.post:find_comments()
   return models.comment:find_all_by_approved_and_post_id{ true,
      self.id }
end

function models.post:find_months(section_ids)
   local months = {}
   local previous_month = {}
   local posts = self:find_all_by_published_and_section_id{
      order = "published_at desc", true, section_ids }
   for _, post in ipairs(posts) do
      local date = os.date("*t", post.published_at)
      if previous_month.month ~= date.month or
	 previous_month.year ~= date.year then
	 previous_month = { month = date.month, year = date.year }
	 months[#months + 1] = previous_month
      end
   end
   return months
end

function models.comment:make_link()
   local author = self.author or strings.anonymous_author
   if self.url and self.url ~= "" then
      return "<a href=\"" .. self.url .. "\">" .. author .. "</a>"
   elseif self.email and self.email ~= "" then
      return "<a href=\"mailto:" .. self.email .. "\">" .. author .. "</a>"
   else
      return author
   end
end

function models.section:find_by_tags(tags)
   return self:find_all("tag like ?", tags)
end

local template_cache = {}

function load_template(name)
   local template = template_cache[name]
   if not template then
      local template_file = io.open("templates/" ..
				    template_name .. "/" .. name, "rb")
      if template_file then
	 template = template_file:read("*a")     
	 template_cache[name] = template
	 template_file:close()
      end
   end
   return template
end

function new_template_env(web)
  local template_env = {}

  template_env.template_vpath = template_vpath or web:link("/template")
  template_env.js_vpath = js_vpath or web:link("/javascripts")
  template_env.today = date(os.time())
  template_env.home_url = web:link("/")
  template_env.home_url_xml = web:link("/xml")

  function template_env.import(arg)
    local plugin_name = arg[1]
    for fname, f in pairs(plugins[plugin_name](web)) do
      template_env[fname] = f
    end
    return ""
  end

  return template_env
end

function new_section_env(web, section)
  local env = new_template_env(web)
  env.id = section.id
  env.title = section.title
  env.description = section.description
  env.tag = section.tag
  env.uri = web:link("/section/" .. section.id)
  return env
end

function new_post_env(web, post, section)
  local env = new_template_env(web)
  env.id = post.id
  env.title = post.title
  env.abstract = post.abstract
  env.body = cosmo.fill(post.body,
    { image_vpath = (image_vpath or web:link("/post")) .. "/" .. post.id })
  env.markdown_body = markdown(env.body)
  env.day_padded = os.date("%d", post.published_at)
  env.day = tonumber(env.day_padded)
  env.month_name = month_names[tonumber(os.date("%m",
    post.published_at))]
  env.month_padded = os.date("%m", post.published_at)
  env.month = tonumber(env.month_padded)
  env.year = tonumber(os.date("%Y", post.published_at))
  env.short_year = os.date("%y", post.published_at)
  env.hour_padded = os.date("%H", post.published_at)
  env.minute_padded = os.date("%M", post.published_at)
  env.hour = tonumber(env.hour_padded)
  env.minute = tonumber(env.minute_padded)
  env.date_string = date(post.published_at)
  if web:empty(post.external_url) then
    env.uri = web:link("/post/" .. post.id)
  else
    env.uri = post.external_url
  end
  env.n_comments = post.n_comments or 0
  env.section_uri = web:link("/section/" .. post.section_id)
  section = section or models.section:find(post.section_id) 
  env.section_title = section.title
  env.image_uri = (image_vpath or web:link("/post")) .. "/" .. post.id ..
    "/" .. (post.image or "")
  env.if_image = cosmo.cond(not web:empty(post.image), env)
  local form_env = {}
  form_env.author = web.input.author or ""
  form_env.email = web.input.email or ""
  form_env.url = web.input.url or ""
  setmetatable(form_env, { __index = env })
  env.if_comment_open = cosmo.cond(post.comment_status ~= "closed", form_env)
  env.if_error_comment = cosmo.cond(not web:empty_param("error_comment"), env)
  env.if_comments = cosmo.cond((post.n_comments or 0) > 0, env)
  env.comments = function (arg, has_block)
    local do_list = function ()
      local comments = post:find_comments()
      for _, comment in ipairs(comments) do
        cosmo.yield(new_comment_env(web, comment))
      end
    end
    if has_block then do_list()
    else
      local template_file = (arg and arg.template) or "comment.html"
      local template = load_template(template_file)
      return cosmo.fill("$do_list[[" .. template .. "]]",
        { do_list = do_list })
    end
  end
  env.add_comment_uri = web:link("/post/" .. post.id .. "/addcomment")
  return env
end

function new_comment_env(web, comment)
  local env = new_template_env(web)
  env.author_link = comment:make_link()
  env.body = comment.body
  env.markdown_body = markdown(env.body)
  env.time_string = time(comment.created_at)
  env.day_padded = os.date("%d", comment.created_at)
  env.day = tonumber(env.day_padded)
  env.month_name = month_names[tonumber(os.date("%m",
    comment.created_at))]
  env.month_padded = os.date("%m", comment.created_at)
  env.month = tonumber(env.month_padded)
  env.year = tonumber(os.date("%Y", comment.created_at))
  env.short_year = os.date("%y", comment.created_at)
  env.hour_padded = os.date("%H", comment.created_at)
  env.minute_padded = os.date("%M", comment.created_at)
  env.hour = tonumber(env.hour_padded)
  env.minute = tonumber(env.minute_padded)
  return env
end

function home_page(web)
   local template = load_template("home.html")
   if template then
      return layout(web, cosmo.fill(template, new_template_env(web)))
   else
      return not_found(web)
   end
end

toycms:dispatch_get(home_page, "/", "/index")

function home_xml(web)
   local template = load_template("home.xml")
   if template then
      web.headers["Content-Type"] = "text/xml"
      return cosmo.fill(template, new_template_env(web))
   else
      return not_found(web)
   end
end

toycms:dispatch_get(home_xml, "/xml")

function view_section(type)
   return function (web, section_id)
	     local section = models.section:find(tonumber(section_id))
	     if not section then return not_found(web) end
	     local template = load_template("section_" .. 
					    tostring(section.tag) .. "." .. type) or
		load_template("section." .. type)
	     if template then
		web.input.section_id = tonumber(section_id)
		local env = new_section_env(web, section)
		if type == "xml" then
		   web.headers["Content-Type"] = "text/xml"
		   return cosmo.fill(template, env)
		else
		   return layout(web, cosmo.fill(template, env))
		end
	     else
		return not_found(web)
	     end
	  end
end

toycms:dispatch_get(view_section("html"), "/section/(%d+)")
toycms:dispatch_get(view_section("xml"), "/section/(%d+)/xml")

function view_post(type)
   return function (web, post_id)
	     local post = models.post:find(tonumber(post_id))
	     if not post then return not_found(web) end
	     local section = models.section:find(post.section_id)
	     local template = load_template("post_" .. 
					    tostring(section.tag) .. "." .. type) or
		load_template("post." .. type)
	     if template then
		web.input.section_id = post.section_id
		web.input.post_id = tonumber(post_id)
		local env = new_post_env(web, post, section)
		if type == "xml" then
		   web.headers["Content-Type"] = "text/xml"
		   return cosmo.fill(template, env)
		else
		   return layout(web, cosmo.fill(template, env))
		end
	     else
		return not_found(web)
	     end
	  end
end

toycms:dispatch_get(view_post("html"), "/post/(%d+)")
toycms:dispatch_get(view_post("xml"), "/post/(%d+)/xml")

function archive(web, year, month)
   local template = load_template("archive.html")
   if template then
      web.input.month = tonumber(month)
      web.input.year = tonumber(year)
      local env = new_template_env(web)
      env.archive_month = web.input.month
      env.archive_month_name = month_names[web.input.month]
      env.archive_year = web.input.year
      env.archive_month_padded = month
      return layout(web, cosmo.fill(template, env))
   else
      not_found(web)
   end
end
  
toycms:dispatch_get(archive, "/archive/(%d+)/(%d+)")

function add_comment(web, post_id)
   if web:empty_param("comment") then
      web.input.error_comment = "1"
      return web:redirect(web:link("/post/" .. post_id, web.input))
   else
      local post = models.post:find(tonumber(post_id))
      if web:empty(post.comment_status) or 
	   post.comment_status == "closed" then
	 return web:redirect(web:link("/post/" .. post_id))
      else
	 local comment = models.comment:new()
	 comment.post_id = post.id
	 local body = web.input.comment:gsub("<", "&lt;"):gsub(">", "&gt;")
	 comment.body = markdown(body)
	 if not web:empty_param("author") then
	    comment.author = web.input.author
	 end
	 if not web:empty_param("email") then
	    comment.email = web.input.email
	 end
	 if not web:empty_param("url") then
	    comment.url = web.input.url
	 end
	 if post.comment_status == "unmoderated" then
	    comment.approved = true
	    post.n_comments = (post.n_comments or 0) + 1
	    post:save()
	 else comment.approved = false end
	 comment:save()
	 return web:redirect(web:link("/post/" .. post_id))
      end
   end
end

toycms:dispatch_post(add_comment, "/post/(%d+)/addcomment")

function get_template_style(web, file_name)
   return toycms:serve_static(web, "templates/" .. 
			      template_name .. "/" .. file_name)
end
 
toycms:dispatch_get(get_template_style, "/template/(.-%.css)", "/template/(.-%.js)")

function get_template_images(web, file_name)
   return toycms:serve_static(web, "templates/" .. 
			      template_name .. "/images/" .. file_name)
end

toycms:dispatch_get(get_template_images, "/template/images/(.-%.gif)",
		    "/template/images/(.-%.jpg)", "/template/images/(.-%.png)")

function get_post_images(web, post_id, file_name)
   return toycms:serve_static(web, "images/" .. post_id .. "/" .. file_name)
end

toycms:dispatch_get(get_post_images, "/post/(%d+)/(.-%.jpg)")

function layout(web, inner_html)
   local layout_template = load_template("layout.html")
   if layout_template then
      local env = new_template_env(web)
      env.view = inner_html
      return cosmo.fill(layout_template, env)
   else
      return inner_html
   end
end

function check_user(web)
  local user_id = web.cookies.user_id
  local password = web.cookies.password
  return models.user:find_by_id_and_password{ user_id, password }
end

