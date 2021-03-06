class SubscriptionsController < ApplicationController

  # GET subscriptions.xml
  def index
    @user = current_user
    if params[:tag] == 'all' || params[:tag].blank?
      @tags = @user.feed_tags
      @feeds = @user.feeds
    else
      @feeds = []
      @tags = Tag.where(id: params[:tag])
    end
    @titles = @user.subscriptions.pluck(:feed_id, :title).each_with_object({}) do |(feed_id, title), hash|
      hash[feed_id] = title
    end
    respond_to do |format|
      format.xml do
        send_data(render_to_string, type: 'text/xml', filename: 'subscriptions.xml')
      end
    end
  end

  # POST /subscriptions
  # POST /subscriptions.json
  def create
    @user = current_user

    feed_urls = [*params[:subscription][:feeds][:feed_url]]
    @results = { success: [], options: [], failed: [] }

    feed_urls.each do |feed_url|
      begin
        finder = FeedFinder.new(feed_url)
        if finder.options.length == 0
          @results[:failed].push(feed_url)
        elsif finder.options.length == 1
          feed = finder.create_feed(finder.options.first)
          if feed
            @user.subscriptions.find_or_create_by(feed: feed)
            @results[:success].push(feed)
          else
            @results[:failed].push(feed_url)
          end
        else
          @results[:options].push(finder.options)
        end
      rescue Exception => e
        logger.info { "exception ---------------------------" }
        logger.info { e.inspect }
        logger.info { e.backtrace.inspect }
        logger.info { "exception ---------------------------" }
        Honeybadger.notify(e)
        @results[:failed].push(feed)
      end
    end

    if @results[:success].any?
      session[:favicon_complete] = false
      @mark_selected = true
      @click_feed = @results[:success].first.id
      get_feeds_list
    end

    respond_to do |format|
      format.js
    end

  end

  # DELETE /subscriptions/1
  # DELETE /subscriptions/1.json
  def destroy
    destroy_subscription(params[:id])
    get_feeds_list
    respond_to do |format|
      format.js
    end
  end

  def feed_destroy
    subscription = @user.subscriptions.where(feed_id: params[:id]).take!
    destroy_subscription(subscription.id)
    get_feeds_list
    respond_to do |format|
      format.js { render 'subscriptions/destroy' }
    end
  end

  def settings_destroy
    destroy_subscription(params[:id])
    redirect_to settings_feeds_url, notice: 'You have successfully unsubscribed.'
  end

  def destroy_subscription(subscription_id)
    @user = current_user
    @subscription = @user.subscriptions.find(subscription_id)
    @subscription.destroy
  end

  def update_multiple
    @user = current_user
    notice = "Feeds updated."
    if params[:operation] && params[:subscription_ids]
      subscriptions = @user.subscriptions.where(id: params[:subscription_ids])
      if params[:operation] == "unsubscribe"
        subscriptions.destroy_all
        notice = "You have unsubscribed."
      elsif params[:operation] == "show_updates"
        subscriptions.update_all(show_updates: true)
      elsif params[:operation] == "hide_updates"
        subscriptions.update_all(show_updates: false)
      elsif params[:operation] == "mute"
        subscriptions.update_all(muted: true)
      elsif params[:operation] == "unmute"
        subscriptions.update_all(muted: false)
      end
    end
    redirect_to settings_feeds_url, notice: notice
  end

  def edit
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    render layout: "settings"
  end

  def update
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    if @subscription.update(subscription_params)
      flash[:notice] = "Settings updated."
    else
      flash[:alert] = "Update failed."
    end
    flash.discard()
  end

  def refresh_favicon
    @user = current_user
    @subscription = @user.subscriptions.find(params[:id])
    FaviconFetcher.perform_async(@subscription.feed.host)
    flash[:notice] = "Favicon will be refreshed shortly"
    flash.discard()
    render 'update'
  end

  private

  def subscription_params
    params.require(:subscription).permit(:muted, :show_updates)
  end

end
