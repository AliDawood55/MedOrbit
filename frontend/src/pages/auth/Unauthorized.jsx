function Unauthorized() {

    return (

        <h1>
            403 - Access Denied
        </h1>

    );

}

<Route

    path="/unauthorized"

    element={<Unauthorized />}

/>


export default Unauthorized;