class UsuariosController < ApplicationController
before_filter :authenticate_usuario!

  def index
    @users = Usuario.all.sort{ |a,b| a.nome.downcase <=> b.nome.downcase }
    @user ||= Usuario.new
  end

  def custom_create
    authorize! :create, Usuario
    create
  end

  def create
    authorize! :create, Usuario
    @user = Usuario.new(params[:usuario])
    if @user.save
      flash[:notice] = I18n.t("devise.registrations.signed_up_another")
    else
      Rails.logger.info(@user.errors.messages.inspect)
      flash[:notice] = I18n.t("usuario.create.failure")
    end
    redirect_to usuarios_path
  end

  def edit
    authorize! :update, Usuario
    @user = Usuario.find(params[:id])
    address = @user.address.nil? ? @user.create_address : @user.address
  end

  def update
    authorize! :update, Usuario
    @user = Usuario.find(params[:id])
    @user.phone params[:usuario][:ddd], params[:usuario][:tel_numero]
    params[:usuario].except! :ddd, :tel_numero


    if @user.update_attributes(params[:usuario])
      Rails.logger.info(@user.errors.messages.inspect)
      flash[:notice] = "Successfully updated Usuario."
      redirect_to usuarios_path
    else
      render :action => 'edit'
    end
  end

  def destroy
    authorize! :destroy, Usuario
    @user = Usuario.find(params[:id])
    if @user.destroy
      flash[:notice] = I18n.t("usuario.delete.sucess")
    end
    redirect_to :back
  end

end
