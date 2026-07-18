import {
    createContext,
    useContext,
    useState
}
    from "react";


const AuthContext = createContext();



export function AuthProvider({ children }) {


    const [user, setUser] = useState(

        JSON.parse(
            localStorage.getItem("user")
        )

    );



    const login = (data) => {


        localStorage.setItem(
            "accessToken",
            data.accessToken
        );


        localStorage.setItem(
            "user",
            JSON.stringify(data.user)
        );



        setUser(data.user);


    };



    const logout = () => {


        localStorage.clear();


        setUser(null);


    };



    return (

        <AuthContext.Provider

            value={{

                user,

                login,

                logout,

                isAuthenticated: !!user

            }}

        >


            {children}


        </AuthContext.Provider>

    );


}



export function useAuth() {

    return useContext(AuthContext);

}