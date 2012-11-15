require "cfoundry"

module BVT::Harness
  class App
    attr_reader :name, :manifest

    def initialize(app, session)
      @app      = app
      @name     = @app.name
      @session  = session
      @log      = @session.log
    end

    def inspect
      "#<BVT::Harness::App '#@name' '#@manifest'>"
    end

    def push(services = nil, appid = nil, need_check = true)
      load_manifest(appid)
      check_framework(@manifest['framework'])
      check_runtime(@manifest['runtime'])
      @manifest['uris'] = [get_url,]

      if @app.exists?
        @app.upload(@manifest['path'])
        restart
        return
      end

      @app.total_instances = @manifest['instances']
      @app.urls            = @manifest['uris'] unless @manifest['no_url']
      @app.framework       = @manifest['framework']
      @app.runtime         = @manifest['runtime']
      @app.memory          = @manifest['memory']
      @app.command         = @manifest['command']

      @log.info "Push App: #{@app.name}"
      begin
        @app.create!
        @app.upload(@manifest['path'])
      rescue Exception => e
        @log.error("Push App: #{@app.name} failed. Manifest: #{@manifest}\n#{e.to_s}")
        raise RuntimeError, "Push App: #{@app.name} failed. Manifest: #{@manifest}\n#{e.to_s}"
      end
      services.each { |service| bind(service, false)} if services
      start(need_check)
    end

    def delete
      @log.info("Delete App: #{@app.name}")
      begin
        @app.delete!
      rescue
        @log.error "Delete App: #{@app.name} failed. "
        raise RuntimeError, "Delete App: #{@app.name} failed."
      end
    end

    def update!(what = {})
      @log.info("Update App: #{@app.name}, what = #{what}")
      begin
        @app.update!(what)
        restart
      rescue Exception => e
        @log.error "Update App: #{@app.name} failed.\n#{e.to_s}"
        raise RuntimeError, "Update App: #{@app.name} failed.\n#{e.to_s}"
      end
    end

    def restart
      stop
      start
    end

    def stop
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end

      unless @app.stopped?
        @log.info "Stop App: #{@app.name}"
        begin
          @app.stop!
        rescue
          @log.error "Stop App: #{@app.name} failed. "
          raise RuntimeError, "Stop App: #{@app.name} failed."
        end
      end
    end

    def start(need_check = true)
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end

      unless @app.running?
        @log.info "Start App: #{@app.name}"
        begin
          @app.start!
        rescue Exception => e
          @log.error "Start App: #{@app.name} failed.\n#{e.to_s}"
          raise RuntimeError, "Start App: #{@app.name} failed.\n#{e.to_s}"
        end
        check_application if need_check
      end
    end

    def bind(service, restart_app = true)
      unless @session.services.collect(&:name).include?(service.name)
        @log.error("Fail to find service: #{service.name}")
        raise RuntimeError, "Fail to find service: #{service.name}"
      end
      begin
        @log.info("Application: #{@app.name} bind Service: #{service.name}")
        @app.bind(service.instance)
      rescue Exception => e
        @log.error("Fail to bind Service: #{service.name} to Application:" +
                       " #{@app.name}\n#{e.to_s}")
        raise RuntimeError, "Fail to bind Service: #{service.name} to " +
            "Application: #{@app.name}\n#{e.to_s}"
      end
      restart if restart_app
    end

    def unbind(service, restart_app = true)
      unless @app.services.collect(&:name).include?(service.name)
        @log.error("Fail to find service: #{service.name} binding to " +
                       "application: #{@app.name}")
        raise RuntimeError, "Fail to find service: #{service.name} binding to " +
            "application: #{@app.name}"
      end

      begin
        @log.info("Application: #{@app.name} unbind Service: #{service.name}")
        @app.unbind(service.instance)
        restart if restart_app
      rescue
        @log.error("Fail to unbind service: #{service.name} for " +
                       "application: #{@app.name}")
        raise RuntimeError, "Fail to unbind service: #{service.name} for " +
            "application: #{@app.name}"
      end
    end

    def stats
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.info("Display application: #{@app.name} status")
        @app.stats
      rescue
        @log.error("Fail to display application: #{@app.name} status!")
        raise RuntimeError, "Fail to display application: #{@app.name} status!"
      end
    end

    def map(url)
      @log.info("Map URL: #{url} to Application: #{@app.name}.")
      @app.urls <<  url
      @app.update!
      @log.debug("Application: #{@app.name}, URLs: #{@app.urls}")
    end

    def unmap(url)
      @log.info("Unmap URL: #{url} to Application: #{@app.name}")
      @app.urls.delete(url)
      @app.update!
      @log.debug("Application: #{@app.name}, URLs: #{@app.urls}")
    end

    def urls
      @log.debug("List URLs: #{@app.urls} of Application: #{@app.name}")
      @app.urls
    end

    def files(path)
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.info("Examine an application: #{@app.name} files")
        @app.files(path)
      rescue
        @log.error("Fail to examine an application: #{@app.name} files!")
        raise RuntimeError, "Fail to examine an application: #{@app.name} files!"
      end
    end

    def file(path)
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.info("Examine an application: #{@app.name} file")
        @app.file(path)
      rescue
        @log.error("Fail to examine an application: #{@app.name} file!")
        raise RuntimeError, "Fail to examine an application: #{@app.name} file!"
      end
    end

    def scale(instance, memory)
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.info("Update the instances/memory: #{instance}/#{memory} " +
                      "for Application: #{@app.name}")
        @app.total_instances = instance.to_i
        @app.memory = memory
        @app.update!
      rescue
        @log.error("Fail to Update the instances/memory limit for " +
                   "Application: #{@app.name} !")
        raise RuntimeError, "Fail to update the instances/memory limit for " +
                   "Application: #{@app.name} !"
      end
    end

    def instances
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.debug("Get application: #{@app.name} instances list")
        @app.instances
      rescue
        @log.error("Fail to list the instances for Application: #{@app.name} !")
        raise RuntimeError, "Fail to list the instances for Application: #{@app.name} !"
      end
    end

    def services
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end
      begin
        @log.debug("Get application: #{@app.name} services list")
        @app.services
      rescue
        @log.error("Fail to list the services for Application: #{@app.name} !")
        raise RuntimeError, "Fail to list the services for Application: #{@app.name} !"
      end
    end

    # only retrieve logs of instance #0
    def logs
      unless @app.exists?
        @log.error "Application: #{@app.name} does not exist!"
        raise RuntimeError, "Application: #{@app.name} does not exist!"
      end

      instance = @app.instances[0]
      body = ""
      instance.files("logs").each do |log|
        body += instance.file(*log)
      end
      @log.debug("Get Application #{@app.name}, logs contents: #{body}")
      body
    end

    def healthy?
      h = @app.healthy?
      unless h
        sleep(0.1)
        h = @app.healthy?
      end
      h
    end

    # method should be REST method, only [:get, :put, :post, :delete] is supported
    def get_response(method, relative_path = "/", data = nil, second_domain = nil)
      unless [:get, :put, :post, :delete].include?(method)
        @log.error("REST method #{method} is not supported")
        raise RuntimeError, "REST method #{method} is not supported"
      end

      path = relative_path.start_with?("/") ? relative_path : "/" + relative_path

      easy              = Curl::Easy.new
      easy.url          = get_url(second_domain) + path
      easy.resolve_mode = :ipv4
      begin
        case method
          when :get
            @log.debug("Get response from URL: #{easy.url}")
            easy.http_get
          when :put
            @log.debug("Put data: #{data} to URL: #{easy.url}")
            easy.http_put(data)
          when :post
            @log.debug("Post data: #{data} to URL: #{easy.url}")
            easy.http_post(data)
          when :delete
            @log.debug("Delete URL: #{easy.url}")
            easy.http_delete
          else nil
        end
        # Time dependency
        # Some app's post is async. Sleep to ensure the operation is done.
        sleep 0.1
        return easy
      rescue Exception => e
        @log.error("Cannot #{method} response from/to #{easy.url}\n#{e.to_s}")
        raise RuntimeError, "Cannot #{method} response from/to #{easy.url}\n#{e.to_s}"
      end
    end

    def load_manifest(appid = nil)
      if !@manifest || appid
        unless VCAP_BVT_APP_ASSETS.is_a?(Hash)
          @log.error("Invalid config file format, #{VCAP_BVT_APP_CONFIG}")
          raise RuntimeError, "Invalid config file format, #{VCAP_BVT_APP_CONFIG}"
        end
        appid ||= @app.name.split('-', 2).last

        unless VCAP_BVT_APP_ASSETS.has_key?(appid)
          @log.error("Cannot find application #{appid} in #{VCAP_BVT_APP_CONFIG}")
          raise RuntimeError, "Cannot find application #{appid} in #{VCAP_BVT_APP_CONFIG}"
        end

        app_manifest = VCAP_BVT_APP_ASSETS[appid].dup
        app_manifest['instances'] = 1 unless app_manifest['instances']
        app_manifest['path']      =
            File.join(File.dirname(__FILE__), "../..", app_manifest['path'])

        #set ENV like this:
        #export VCAP_BVT_RUNTIME='{:ruby=>"ruby19", :java=>"java6"}'
        category = app_manifest['category']

        if category.nil? || category == ""
          @log.debug("Cannot find category option for #{appid} in #{VCAP_BVT_APP_CONFIG}")
        else
          runtime = eval(ENV['VCAP_BVT_RUNTIME'])[category.to_sym] unless ENV['VCAP_BVT_RUNTIME'].nil?
          runtime ||= VCAP_BVT_INFO_RUNTIME[category.to_sym].first
          app_manifest['runtime'] = runtime
        end

        @manifest = app_manifest
      end
    end

    def get_url(second_domain = nil)
      # URLs synthesized from app names containing '_' are not handled well
      # by the Lift framework.
      # So we used '-' instead of '_'
      # '_' is not a valid character for hostname according to RFC 822,
      # use '-' to replace it.
      second_domain = "-#{second_domain}" if second_domain
      "#{@app.name}#{second_domain}.#{@session.TARGET.gsub("http://api.", "")}".gsub("_", "-")
    end

    private

    def check_framework(framework)
      unless VCAP_BVT_SYSTEM_FRAMEWORKS.has_key?(framework.to_sym)
        @log.error("Framework: #{framework} is not available " +
                       "on target: #{@session.TARGET}")
        raise RuntimeError, "Framework: #{framework} is not available " +
                    "on target: #{@session.TARGET}"
      end
    end

    def check_runtime(runtime)
      unless VCAP_BVT_SYSTEM_RUNTIMES.has_key?(runtime)
        @log.error("Runtime: #{runtime} is not available on target: #{@session.TARGET}")
        raise RuntimeError, "Runtime: #{runtime} is not available" +
            " on target: #{@session.TARGET}"
      end
    end

    def check_application
      seconds = 0
      until @app.healthy?
        sleep 1
        seconds += 1
        if seconds == VCAP_BVT_APP_ASSETS['timeout_secs']
          sleep 2
          unless @app.healthy?
            @log.error "Application: #{@app.name} cannot be started " +
                         " in #{VCAP_BVT_APP_ASSETS['timeout_secs']} seconds"
            raise RuntimeError, "Application: #{@app.name} cannot be started " +
              "in #{VCAP_BVT_APP_ASSETS['timeout_secs']} seconds"
          end
        end
      end
    end
  end
end
